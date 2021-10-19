#pragma once

#ifdef __cplusplus
extern "C" {
#endif

#include "small/mempool.h"
struct txn;
struct tuple;

enum TX_ALLOC_TYPE {
	TX_ALLOC_TRACKER = 0,
	TX_ALLOC_STORY = 1,
	TX_ALLOC_SVP = 2,
	TX_ALLOC_STMT = 3,
	TX_ALLOC_LOG = 4,
	TX_ALLOC_USER_DATA = 5,
	TX_ALLOC_TRIGGER = 6,
	TX_PIN_TUPLE = 7,
	TX_ALLOC_MAX = 8
};

struct txn_stat_info {
	uint64_t min[TX_ALLOC_MAX];
	uint64_t max[TX_ALLOC_MAX];
	uint64_t avg[TX_ALLOC_MAX];
	uint64_t total[TX_ALLOC_MAX];
};

/**
 * @brief Return stats collected by stat manager of memtx.
 * @param out stats min, max, avg and total for every statistic.
 */
void
tx_stat_get_stats(struct txn_stat_info *stats);

/**
 * @brief A wrapper over region_alloc.
 * @param txn Owner of a region
 * @param size Bytes to allocate
 * @param alloc_type See TX_ALLOC_TYPE
 * @note The only way to truncate a region of @a txn is to clear it.
 */
void *
tx_region_alloc(struct txn *txn, size_t size, int alloc_type);

/**
 * @brief Register @a txn in @a tx_stat. It is very important
 * to register txn before using allocators from @a tx_stat.
 */
void
tx_stat_register_txn(struct txn *txn);

/**
 * @brief Unregister @a txn and truncate its region up to sizeof(txn).
 */
void
tx_stat_clear_txn(struct txn *txn);

/**
 * @brief Transfer an allocation of @a size bytes of @a alloc_type type
 * from @a old_txn to @a new_txn.
 */
void
tx_rebind_allocation(struct txn *old_txn, struct txn *new_txn, size_t size,
		      int alloc_type);

/**
 * @brief A wrapper over region_aligned_alloc.
 * @param txn Owner of a region
 * @param size Bytes to allocate
 * @param alignment Alignment of allocation
 * @param alloc_type See TX_ALLOC_TYPE
 */
void *
tx_region_aligned_alloc(struct txn *txn, size_t size, size_t alignment,
			int alloc_type);

#define tx_region_alloc_object(txn, T, size, alloc_type) ({		            \
	*(size) = sizeof(T);							    \
	(T *)tx_region_aligned_alloc((txn), sizeof(T), alignof(T), (alloc_type));   \
})

/**
 * @brief A wrapper over mempool_alloc.
 * @param txn Txn that requires an allocation.
 * @param pool Mempool to allocate from.
 * @param alloc_type See TX_ALLOC_TYPE
 */
void *
tx_mempool_alloc(struct txn *txn, struct mempool *pool, int alloc_type);

/**
 * @brief A wrapper over mempool_free.
 * @param txn Txn that requires a deallocation.
 * @param pool Mempool to deallocate from.
 * @param ptr Pointer to free.
 * @param alloc_type See TX_ALLOC_TYPE.
 */
void
tx_mempool_free(struct txn *txn, struct mempool *pool, void *ptr, int alloc_type);

/**
 * @brief Notify that @a tuple is referenced by @a txn
 * but is not being placed in any space and is pinned.
 */
void
tx_pin_tuple(struct txn *txn, struct tuple *tuple);

/**
 * @brief Notify that @a tuple referenced by @a txn
 * was inserted into a space and is not pinned anymore.
 */
void
tx_release_tuple(struct txn *txn, struct tuple *tuple);

/**
 * @brief Transfer ownership over pinned @a tuple from
 * @a old_txn to @a new_txn
 */
void
tx_repin_tuple(struct txn *old_txn, struct txn *new_txn, struct tuple *tuple);

#ifndef NDEBUG
/**
 * @brief Check if @a tuple is pinned.
 * @note This function is available only in debug mode.
 */
bool
tx_tuple_is_pinned(struct tuple *tuple);
#endif

void
tx_stat_init();

void
tx_stat_free();

#ifdef __cplusplus
}
#endif
