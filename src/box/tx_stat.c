#include <assert.h>
#include "small/mempool.h"
#include "small/region.h"
#include "histogram.h"
#include "tx_stat.h"
#include "txn.h"
#include "fiber.h"
#include "tuple.h"
#include <lib/core/say.h>

static uint32_t
txn_stat_key_hash(const struct txn *a)
{
	uintptr_t u = (uintptr_t)a;
	if (sizeof(uintptr_t) <= sizeof(uint32_t))
		return u;
	else
		return u ^ (u >> 32);
}

struct txn_stat {
	struct txn *txn;
	int64_t stats[TX_ALLOC_MAX];
};

#define mh_name _txn_stats
#define mh_key_t struct txn *
#define mh_node_t struct txn_stat *
#define mh_arg_t int
#define mh_hash(a, arg) (txn_stat_key_hash((*(a))->txn))
#define mh_hash_key(a, arg) (txn_stat_key_hash(a))
#define mh_cmp(a, b, arg) ((*(a))->txn != (*(b))->txn)
#define mh_cmp_key(a, b, arg) ((a) != (*(b))->txn)
#define MH_SOURCE
#include "salad/mhash.h"

struct txn_stat_storage {
	struct histogram *hist;
	int64_t total;
	int32_t obj_count;
};

#ifndef NDEBUG
struct pinned_tuple {
	struct tuple *tuple;
	struct txn *owner;
};

static uint32_t
pinned_tuple_key_hash(const struct tuple *a)
{
	uintptr_t u = (uintptr_t)a;
	if (sizeof(uintptr_t) <= sizeof(uint32_t))
		return u;
	else
		return u ^ (u >> 32);
}

#define mh_name _pinned_tuple
#define mh_key_t struct tuple *
#define mh_node_t struct pinned_tuple *
#define mh_arg_t int
#define mh_hash(a, arg) (pinned_tuple_key_hash((*(a))->tuple))
#define mh_hash_key(a, arg) (pinned_tuple_key_hash(a))
#define mh_cmp(a, b, arg) ((*(a))->tuple != (*(b))->tuple)
#define mh_cmp_key(a, b, arg) ((a) != (*(b))->tuple)
#define MH_SOURCE
#include "salad/mhash.h"

#endif

struct txn_stat_manager {
	struct txn_stat_storage stats_storage[TX_ALLOC_MAX];
	struct mh_txn_stats_t *stats;
	struct mempool stat_item_pool;
#ifndef NDEBUG
	struct mempool pinned_tuple_item_pool;
	struct mh_pinned_tuple_t *pinned_tuples;
#endif
};

static struct txn_stat_manager memtx_tx_stat_manager;

void
tx_track_allocation(struct txn *txn, int64_t alloc_size, int alloc_type)
{
	assert(alloc_type < TX_ALLOC_MAX);
	mh_int_t pos = mh_txn_stats_find(memtx_tx_stat_manager.stats, txn, 0);
	assert(pos != mh_end(memtx_tx_stat_manager.stats));
	struct txn_stat *stat = *mh_txn_stats_node(memtx_tx_stat_manager.stats, pos);
	histogram_discard(memtx_tx_stat_manager.stats_storage[alloc_type].hist,
			  stat->stats[alloc_type]);
	assert(alloc_size >= 0 || stat->stats[alloc_type] + alloc_size >= 0);
	stat->stats[alloc_type] += alloc_size;
	histogram_collect(memtx_tx_stat_manager.stats_storage[alloc_type].hist,
			  stat->stats[alloc_type]);
}

void
tx_stat_register_txn(struct txn *txn)
{
	struct txn_stat *new_stat =
		mempool_alloc(&memtx_tx_stat_manager.stat_item_pool);
	memset(new_stat, 0, sizeof(struct txn_stat));
	new_stat->txn = txn;
	for (size_t i = 0; i < TX_ALLOC_MAX; ++i) {
		assert(new_stat->stats[i] == 0);
		histogram_collect(memtx_tx_stat_manager.stats_storage[i].hist, 0);
	}
	const struct txn_stat **new_stat_p =
		(const struct txn_stat **)&new_stat;
	struct txn_stat **ret = NULL;
	mh_txn_stats_put(memtx_tx_stat_manager.stats, new_stat_p, &ret, 0);
	assert(ret == NULL);
}

static void
txn_stat_forget(struct txn_stat *txn_stat)
{
	assert(txn_stat != NULL);
	mh_int_t pos = mh_txn_stats_find(memtx_tx_stat_manager.stats,
					 txn_stat->txn, 0);
	assert(pos != mh_end(memtx_tx_stat_manager.stats));
	mh_txn_stats_del(memtx_tx_stat_manager.stats, pos, 0);
	mempool_free(&memtx_tx_stat_manager.stat_item_pool, txn_stat);
}

void
tx_rebind_allocation(struct txn *old_txn, struct txn *new_txn, size_t size,
		      int alloc_type)
{
	tx_track_allocation(old_txn, -1 * (int64_t)size, alloc_type);
	tx_track_allocation(new_txn, (int64_t)size, alloc_type);
}

void
tx_stat_get_stats(struct txn_stat_info *stats)
{
	assert(stats != NULL);

	struct txn_stat_storage *stat_storage = memtx_tx_stat_manager.stats_storage;
	for (int i = 0; i < TX_ALLOC_MAX; ++i) {
		stats->max[i] = stat_storage[i].hist->max;
		stats->min[i] = histogram_percentile_lower(stat_storage[i].hist, 0);
		stats->total[i] = stat_storage[i].total;
		stats->avg[i] = stat_storage[i].total / stat_storage[i].obj_count;
	}
}

void *
tx_mempool_alloc(struct txn *txn, struct mempool* pool, int alloc_type)
{
	assert(pool != NULL);
	assert(alloc_type >= 0 && alloc_type < TX_ALLOC_MAX);

	struct mempool_stats pool_stats;
	mempool_stats(pool, &pool_stats);
	tx_track_allocation(txn, pool_stats.objsize, alloc_type);
	return mempool_alloc(pool);
}

void
tx_mempool_free(struct txn *txn, struct mempool *pool, void *ptr, int alloc_type)
{
	assert(pool != NULL);
	assert(alloc_type >= 0 && alloc_type < TX_ALLOC_MAX);

	struct mempool_stats pool_stats;
	mempool_stats(pool, &pool_stats);
	tx_track_allocation(txn, -1 * (int64_t)pool_stats.objsize,
			    alloc_type);
	mempool_free(pool, ptr);
}

void *
tx_region_alloc(struct txn *txn, size_t size, int alloc_type)
{
	assert(txn != NULL);
	assert(alloc_type >= 0 && alloc_type < TX_ALLOC_MAX);

	tx_track_allocation(txn, (int64_t)size, alloc_type);
	return region_alloc(&txn->region, size);
}

void *
tx_region_aligned_alloc(struct txn *txn, size_t size, size_t alignment,
			int alloc_type)
{
	assert(txn != NULL);
	assert(alloc_type >= 0 && alloc_type < TX_ALLOC_MAX);

	tx_track_allocation(txn, (int64_t)size, alloc_type);
	return region_aligned_alloc(&txn->region, size, alignment);
}

void
tx_stat_clear_txn(struct txn *txn)
{
	assert(txn != NULL);
	region_truncate(&txn->region, sizeof(struct txn));
	mh_int_t pos = mh_txn_stats_find(memtx_tx_stat_manager.stats, txn, 0);
	assert(pos != mh_end(memtx_tx_stat_manager.stats));
	struct txn_stat *stat = *mh_txn_stats_node(memtx_tx_stat_manager.stats, pos);
	for (int i = 0; i < TX_ALLOC_MAX; ++i) {
		// TODO: check that non-region allocations were deleted.
		histogram_discard(memtx_tx_stat_manager.stats_storage[i].hist,
				  stat->stats[i]);
		memtx_tx_stat_manager.stats_storage[i].obj_count--;
	}
	txn_stat_forget(stat);
}

void
tx_stat_init()
{
	mempool_create(&memtx_tx_stat_manager.stat_item_pool, cord_slab_cache(), sizeof(struct txn_stat));
	memtx_tx_stat_manager.stats = mh_txn_stats_new();
	int64_t buckets[] = {1, 2, 3, 5, 10, 1000, 10000, 100000};
	for (size_t i = 0; i < TX_ALLOC_MAX; ++i) {
		memtx_tx_stat_manager.stats_storage[i].hist = histogram_new(buckets, lengthof(buckets));
		histogram_collect(memtx_tx_stat_manager.stats_storage[i].hist, 0);
	}
	tx_stat_register_txn(NULL);

#ifndef NDEBUG
	mempool_create(&memtx_tx_stat_manager.pinned_tuple_item_pool, cord_slab_cache(), sizeof(struct pinned_tuple));
	memtx_tx_stat_manager.pinned_tuples = mh_pinned_tuple_new();
#endif
}

void
tx_stat_free()
{
	mempool_destroy(&memtx_tx_stat_manager.stat_item_pool);
	for (size_t i = 0; i < TX_ALLOC_MAX; ++i) {
		histogram_delete(memtx_tx_stat_manager.stats_storage[i].hist);
	}
	mh_txn_stats_delete(memtx_tx_stat_manager.stats);

#ifndef NDEBUG
	mempool_destroy(&memtx_tx_stat_manager.pinned_tuple_item_pool);
	mh_pinned_tuple_delete(memtx_tx_stat_manager.pinned_tuples);
#endif
}

void
tx_pin_tuple(struct txn *txn, struct tuple *tuple)
{
#ifndef NDEBUG
	say_debug("Pin tuple %p with txn %p and size %lu", tuple, txn,
		 tuple_size(tuple));
	struct pinned_tuple *pinned =
		mempool_alloc(&memtx_tx_stat_manager.pinned_tuple_item_pool);
	assert(pinned != NULL);
	pinned->owner = txn;
	pinned->tuple = tuple;
	const struct pinned_tuple **pinned_tuple_p =
		(const struct pinned_tuple **)&pinned;
	struct pinned_tuple *pinned_ret = NULL;
	struct pinned_tuple **ret = &pinned_ret;
	mh_pinned_tuple_put(memtx_tx_stat_manager.pinned_tuples,
			    pinned_tuple_p, &ret, 0);
	assert(ret == NULL);
#endif
	tx_track_allocation(txn, (int64_t)tuple_size(tuple), TX_PIN_TUPLE);
}

void
tx_release_tuple(struct txn *txn, struct tuple *tuple)
{
#ifndef NDEBUG
	say_debug("Release tuple %p with txn %p and size %lu", tuple, txn,
		 tuple_size(tuple));
	mh_int_t pos = mh_pinned_tuple_find(memtx_tx_stat_manager.pinned_tuples,
					    tuple, 0);
	assert (pos != mh_end(memtx_tx_stat_manager.pinned_tuples));
	struct pinned_tuple *pinned =
		*mh_pinned_tuple_node(memtx_tx_stat_manager.pinned_tuples, pos);
	assert(pinned->owner == txn);
	mh_pinned_tuple_del(memtx_tx_stat_manager.pinned_tuples, pos, 0);
	mempool_free(&memtx_tx_stat_manager.pinned_tuple_item_pool, pinned);
#endif
	tx_track_allocation(txn, -1 * (int64_t)tuple_size(tuple),TX_PIN_TUPLE);
}

void
tx_repin_tuple(struct txn *old_txn, struct txn *new_txn, struct tuple *tuple)
{
	tx_release_tuple(old_txn, tuple);
	tx_pin_tuple(new_txn, tuple);
}

#ifndef NDEBUG
bool
tx_tuple_is_pinned(struct tuple *tuple)
{
	mh_int_t pos = mh_pinned_tuple_find(memtx_tx_stat_manager.pinned_tuples,
					    tuple, 0);
	return pos != mh_end(memtx_tx_stat_manager.pinned_tuples);
}
#endif