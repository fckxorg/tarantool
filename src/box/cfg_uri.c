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

void
cfg_uri_array_destroy(struct cfg_uri_array *uri_array)
{
	(void)uri_array;
}

int
cfg_uri_array_create(struct cfg_uri_array *uri_array, const char *option_name)
{
	if (cfg_get_uri_array(option_name) != 0)
		goto fail;
	uri_array->uri = lua_tostring(tarantool_L, -1);
	lua_pop(tarantool_L, 1);
	return 0;
fail:
	cfg_uri_array_destroy(uri_array);
	return -1;
}
