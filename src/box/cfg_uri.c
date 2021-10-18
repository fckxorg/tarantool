/*
 * Copyright 2010-2021, Tarantool AUTHORS, please see AUTHORS file.
 *
 * Redistribution and use in source and binary forms, with or
 * without modification, are permitted provided that the following
 * conditions are met:
 *
 * 1. Redistributions of source code must retain the above
 *    copyright notice, this list of conditions and the
 *    following disclaimer.
 *
 * 2. Redistributions in binary form must reproduce the above
 *    copyright notice, this list of conditions and the following
 *    disclaimer in the documentation and/or other materials
 *    provided with the distribution.
 *
 * THIS SOFTWARE IS PROVIDED BY <COPYRIGHT HOLDER> ``AS IS'' AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED
 * TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
 * A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL
 * <COPYRIGHT HOLDER> OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT,
 * INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 * DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
 * SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR
 * BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF
 * LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 * (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF
 * THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
 * SUCH DAMAGE.
 */
#include "cfg_uri.h"
#include "tt_static.h"
#include "lua/utils.h"
#include "diag.h"
#include "box/error.h"
#include "box/errcode.h"
#include "trivia/util.h"

enum {
	MAX_OPT_NAME_LEN = 256,
};

enum {
	CFG_URI_OPTION_HOST = 0,
	CFG_URI_OPTION_TRANSPORT = 1,
	CFG_URI_OPTION_MAX
};

static int
cfg_get_uri_array(const char *param)
{
	const char *buf =
		tt_snprintf(MAX_OPT_NAME_LEN,
			    "return box.internal.cfg_get_%s(box.cfg.%s)",
			    param, param);
	if (luaL_dostring(tarantool_L, buf) != 0)
		return -1;
	return 0;
}

static void
cfg_uri_get_option(struct cfg_uri_option *uri_option)
{
	if (lua_isnil(tarantool_L, -1))
		return;
	assert(lua_istable(tarantool_L, -1));
	uri_option->size = lua_objlen(tarantool_L, -1);
	if (uri_option->size == 0)
		return;
	uri_option->values =
		(const char **)xcalloc(uri_option->size, sizeof(char *));
	for (int i = 0; i < uri_option->size; i++) {
		lua_rawgeti(tarantool_L, -1, i + 1);
		uri_option->values[i] = lua_tostring(tarantool_L, -1);
		lua_pop(tarantool_L, 1);
	}
}

static void
cfg_uri_destroy(struct cfg_uri *uri)
{
	free(uri->transport.values);
}

static void
cfg_uri_init(struct cfg_uri *uri)
{
	memset(uri, 0, sizeof(struct cfg_uri));
}

static void
cfg_uri_get(struct cfg_uri *uri, int idx)
{
	const char *cfg_uri_options[CFG_URI_OPTION_MAX] = {
		/* CFG_URI_OPTION_HOST */      "uri",
		/* CFG_URI_OPTION_TRANSPORT */ "transport",
	};
	for (unsigned i = 0; i < lengthof(cfg_uri_options); i++) {
		lua_rawgeti(tarantool_L, -1, idx + 1);
		lua_pushstring(tarantool_L, cfg_uri_options[i]);
		lua_gettable(tarantool_L, -2);
		switch (i) {
		case CFG_URI_OPTION_HOST:
			assert(lua_isstring(tarantool_L, -1));
			uri->host = lua_tostring(tarantool_L, -1);
			break;
		case CFG_URI_OPTION_TRANSPORT:
			cfg_uri_get_option(&uri->transport);
			break;
		default:
			unreachable();
		}
		lua_pop(tarantool_L, 2);
	}
}

void
cfg_uri_array_destroy(struct cfg_uri_array *uri_array)
{
	for (int i = 0; i < uri_array->size; i++)
		cfg_uri_destroy(&uri_array->uris[i]);
	free(uri_array->uris);
}

int
cfg_uri_array_create(struct cfg_uri_array *uri_array, const char *option_name)
{
	memset(uri_array, 0, sizeof(struct cfg_uri_array));
	if (cfg_get_uri_array(option_name) != 0)
		return -1;
	if (lua_isnil(tarantool_L, -1))
		goto finish;
	assert(lua_istable(tarantool_L, -1));
	int size = lua_objlen(tarantool_L, -1);
	assert(size > 0);
	uri_array->uris =
		(struct cfg_uri *)xcalloc(size, sizeof(struct cfg_uri));
	for (uri_array->size = 0; uri_array->size < size; uri_array->size++) {
		int i = uri_array->size;
		cfg_uri_init(&uri_array->uris[i]);
		cfg_uri_get(&uri_array->uris[i], i);
	}
finish:
	lua_pop(tarantool_L, 1);
	return 0;
}
