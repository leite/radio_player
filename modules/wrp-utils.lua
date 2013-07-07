module("utils", package.seeall)

local utils, json, io, os, co, st, tb = 
      {}, require('json'), require('io'), require('os'), require('coroutine'), require('string'), require('table')

local default, scapes = {
  last_fm = {
    key        = '71e3c271bf0cb0f938a996628566b546',
    secret     = '1e1400c452cf23f95c1992b6a7af92be',
    base_point = 'http://ws.audioscrobbler.com/2.0/',
    auth_point = 'http://www.last.fm/api/auth/',
    token      = '',
    authorized = false,
    busy_state = false,
    session = {
      user = '',
      key  = ''
    }
  },
  pidgin = {
    status        = '',
    message       = '',
    should_change = false
  },
  meta = {  
    last    = {artist='', song=''},
    current = {artist='', song=''}
  }
}, {
  ["\\"] = "\\\\",
  ["\0"] = "\\0",
  ["\n"] = "\\n",
  ["\r"] = "\\r",
  ["\t"] = "\\t",
  quote  = '"',
  quote2 = '"',
  ["["]  = '[',
  ["]"]  = ']'
}

local function escape_it(scape) 
  return scapes[scape] or scape
end

local function sort_it(a, b)
  return a.k==b.k and (a.v<b.v) or (a.k<b.k)
end

local function dump(data, depth)
  local t = type(data)
  if t=='string' then
    return scapes.quote .. st.gsub(data, "%c", escape_it) .. scapes.quote2
  elseif t=='table' then 
    local indent, is_array, estimate, i, lines, source = st.rep(' ', depth), true, 0, 1, {}, ''
    for k,v in pairs(data) do 
      if not (k==i) then is_array=false end
      i = i+1 
    end
    i = 1
    for k,v in (is_array and ipairs or pairs)(data) do
      s        = is_array and '' or ((type(k)=='string' and 
        st.find(k, "^[%a_][%a%d_]*$")~=nil) and k..' = ' or 
        '['..dump(k, depth+2)..'] = ')
      s        = s..dump(v, depth+2)
      lines[i] = s
      estimate = estimate + #s
      i        = i + 1
    end
    return estimate>200 and 
        "{\n"..indent.. tb.concat(lines, ",\n"..indent) .."\n".. st.rep(' ', depth-2) .."}" or 
        "{".. tb.concat(lines, ", ") .."}"
  else
    return tostring(data)
  end
end

local function merge_tables(t1, t2)
  for key,value in pairs(t2) do
    t1[key] = value
  end
end

function utils:debug(...)
  local args, i = {...}, 1
  for i=1, #args do
    args[i] = dump(args[i], 2)
  end
  vlc.msg.warn(tb.concat(args, "\t"))
end

function utils:escape(str)
  if not str then
    return ''
  end
  return st.gsub(
            st.gsub(str, '\n', '\r\n'), 
            '([^%w])', 
            function(c) return st.format('%%%02X', st.byte(c)) end
          )
end

function utils:unescape(str)
  if not str then
    return ''
  end
  return st.gsub(
            str, 
            "%%(%x%x)", 
            function(h) return st.char(tonumber(h, 16)) end
          )
end

function utils:md5(string)
  local handler = io.popen('printf "'.. string ..'" | md5sum')
  --local handler = io.popen('echo "'.. string ..'" | md5sum')
  return st.sub(handler:read("*a"), 1, 32)
end

-- build query string for last.fm: order query keys, escape values and generate md5 of its contents
function utils:build_query(query)
  local a_query, sig, st_query = {}, '', ''

  for key, val in pairs(query) do
    tb.insert(a_query, {k=key, v=val})
  end

  tb.sort(a_query, sort_it)

  for i=1, #a_query do
    st_query = st.format('%s%s=%s&', st_query, self:escape(a_query[i].k), self:escape(a_query[i].v))
    sig      = st.format('%s%s%s', sig, a_query[i].k, a_query[i].v)
  end


end

function utils:fetch(url, callback)
  self:debug('fetch_url')
  local async_stream = co.create(
    function(url)
      local handler, err, output, read = 
        nil, nil, nil, nil

      self:debug(url)

      handler, err = vlc.stream(url)
      if not handler then
        self:debug('not handler')
        callback(nil, err)
      else
        -- check if it is json, xml? ... not yet
        output  = handler:read(65653)
        handler = nil

        self:debug(output)

        local parsed_json = json:decode(st.gsub(output, "^[%c%s]*(.-)[%c%s]*$", "%1"))
        --if is_ok then
        callback(parsed_json, nil)
        --else
        --  callback(nil, parsed_json)
        --end
      end
    end)

  co.resume(async_stream, url)
end

function utils:cfg_save(settings)
  local cfg, err = io.open(vlc.config.configdir() .. "/.wrp", "w")
  if not cfg then
    self:debug("error opening .wrp for writing: " .. err) return
  end
  cfg:write(json:encode(settings))
  cfg:close()
end

function utils:cfg_load(settings)
  local cfg, err = io.open(vlc.config.configdir() .. "/.wrp", "r")
  if not cfg then
    self:debug("error opening .wrp for reding: " .. err)
    merge_tables(settings, default)
    return
  end
  local data = cfg:read("*a")
  merge_tables(settings, (data=='' and default or json:decode(data)))
  cfg:close()
end

function utils:get_pidgin_defaults(pidgin_data)
  -- gather pidgin message
  local hnd = nil
  hnd = io.popen("purple-remote getstatus")
  pidgin_data.status = st.gsub(hnd:read("*a"), '[%c]*', '')
  hnd:close()

  hnd = io.popen("purple-remote getstatusmessage")
  pidgin_data.message = self:unescape(st.match(hnd:read("*a"), '[%c%s]*([^\n?%c]*)[%c]*'))
  hnd:close()
end

function utils:set_pidgin(...)
  local message, status = ...
  if message~=nil and status~=nil then
    os.execute(st.format('purple-remote "setstatus?status=%s&message=%s"', status, self:escape(message)))
  elseif message~=nil and status==nil then
    os.execute(st.format('purple-remote "setstatus?message=%s"', self:escape(message)))
  else
    os.execute(st.format('purple-remote "setstatus?status=%s"', status))
  end
end

function utils:set_pidgin_defaults(pidgin_data)
  os.execute(
    st.format(
        'purple-remote "setstatus?status=%s&message=%s"',
        pidgin_data.status,
        self:escape(pidgin_data.message)
      )
    )
end

function utils:scrobbler_now_playing(artist, song, callback)
--[[
  artist (Required)  : The artist name.
  track (Required)   : The track name.
--  
  api_key (Required) : A Last.fm API key.
  api_sig (Required) : A Last.fm method signature. See authentication for more information.
  sk (Required)      : A session key generated by authenticating a user via the authentication protocol.
--]]
  

end

function utils:scrobbler_scrobble(artist, song, callback)

end

function utils:scrobbler_love(artist, song, callback)

end

function utils:scrobbler_unlove(artist, song, callback)
  
end

setmetatable(utils, {__index=utils})
return utils