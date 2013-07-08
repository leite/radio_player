-- ----------------------------------------------------------------------------
-- "THE BEER-WARE LICENSE" (Revision 42):
-- <xxleite@gmail.com> wrote this file. As long as you retain this notice you
-- can do whatever you want with this stuff. If we meet some day, and you think
-- this stuff is worth it, you can buy me a beer in return
-- ----------------------------------------------------------------------------

--[[
  http://apps.simbio.se#wrpvlc
  http://apps.simbio.se/wrpvlc/callback

  -- about: play web radio streams, list radios, parse title/artist and scroobbles
  Key: 71e3c271bf0cb0f938a996628566b546
  Secret: 1e1400c452cf23f95c1992b6a7af92be

--]]

local string, os, utils, core = 
  require('string'), require('os'), require('wrp-utils'), nil


local stations = {
  { name = "Ska",         url = "http://listen.sky.fm/public1/ska.pls" },
  { name = "Drum & Bass", url = "http://listen.di.fm/public2/drumandbass.pls" },
  { name = "liquid DnB",  url = "http://listen.di.fm/public2/liquiddnb.pls" },
  { name = "Metal",       url = "http://listen.sky.fm/public1/metal.pls" },
  { name = "Modern Rock", url = "http://listen.sky.fm/public1/modernrock.pls" }
}

--
local dlg, last_fm, pidgin, auth_state, play_count =
  nil, nil, nil, false, 0

function descriptor()
  return { 
    title       = "Web Radio for VLC",
    version     = "0.1",
    author      = "xxleite",
    description = "Web Radio Player for VideoLan"
  }
end

function activate()
  --
  core    = utils:new()
  --
  dlg     = vlc.dialog("Web Radio")
  last_fm = dlg:add_button((core.last_fm.authorized and "scrobbling" or "scrobble ?"), click_authorize, 1, 1, 1, 1)
  pidgin  = dlg:add_button((core.pidgin.should_change and "notifying" or "notify ?"), click_notify, 2, 1, 1, 1)
  list    = dlg:add_list(1, 3, 4, 1)
  play    = dlg:add_button("Play", click_play, 1, 4, 4, 1)
  -- add stations
  for idx, details in ipairs(stations) do
    list:add_value(details.name, idx)
  end

  core:get_pidgin_defaults()

  core:debug("activate")
  core:debug(core)
  dlg:show()
end

-- *********************
-- Authorization Process
-- *********************
-- check if user authorized this app
function auth_callback(data, msg)
  core:debug("authorized?")
  core:debug(data)
  if not data then
    core:debug('no data in authorization callback')
    core.last_fm.authorized = false
    auth_state              = false
    return
  end

  if data.error then
    core:debug('error in authorization callback ... '..data.error)
    if data.error==4 or data.error==15 or data.error==14 then
      core.last_fm.token = ''
      auth_state         = false
      last_fm:set_text('scrobble ?')
    else
      auth_state = false
    end
    core.last_fm.authorized = false
    return
  end

  if data.session then
    core.last_fm.session.user = data.session.name
    core.last_fm.session.key  = data.session.key
    core.last_fm.authorized   = true
    auth_state                = true
    last_fm:set_text('scrobbling')
  end
end

-- token callback
function token_callback(data, msg)
  if not data or data.error then
    core.last_fm.token = ''
    auth_state        = false
    last_fm:set_text('scrobble ?')
    return
  end

  os.execute(
    string.format(
      'exec $(which firefox || which google-chrome || which chromium-browser) "%s?api_key=%s&token=%s">/dev/null & echo $!',
      core.last_fm.auth_point,
      core.last_fm.key,
      data.token
    )
  )

  core.last_fm.token = data.token
  auth_state         = false
  last_fm:set_text('authorized ?')
end

function click_play()
  local selection, sel = list:get_selection(), nil
  if not selection then 
    return 1 
  end
  for idx, _ in pairs(selection) do
    sel = idx break
  end
  details = stations[sel]

  -- Play the selected radio station
  vlc.playlist.clear()
  vlc.playlist.add({{path=details.url, title=details.name, name=details.name}})
  vlc.playlist.play()
  core:debug('clicked')
end

function click_notify()
  core.pidgin.should_change = true
  pidgin:set_text("notifying")
end

function click_authorize()
  core:debug('click_authorize')
  core:debug(auth_state, core.last_fm.token)
  if auth_state then
    core:debug('auth_state')
    return
  end  

  if core.last_fm.token~='' then
    -- next stage, check if user autorized
    core:debug('next stage, check if user autorized')
    auth_state = true
    --
    core:fetch(
        core.last_fm.base_point ..'?'..
        core:build_query(
          {
            method  = 'auth.getSession',
            token   = core.last_fm.token,
            api_key = core.last_fm.key,
            format  = 'json'
          }, 
          core.last_fm.secret
        ),
        auth_callback
      )
  elseif not auth_state and core.last_fm.token=='' then
    -- fetch token
    core:debug('fetch token')
    auth_state = true
    core:fetch(
        core.last_fm.base_point ..'?'..
        core:build_query(
          {
            method  = 'auth.gettoken',
            api_key = core.last_fm.key,
            format  = 'json'
          }
        ),
        token_callback
      )
  end
end

-- 
function meta_changed()
  local metas = vlc.input.item():metas()

  if metas.now_playing then
    local artist, song = nil, nil
    
    artist, song = string.match(metas.now_playing, "%s*(.-)%s+%-%s+(.-)%s*$")
    if not artist or not song then
      artist, song = string.match(metas.now_playing, "%s*(.-)%s*%-%s*(.-)%s*$")
    end

    if core.meta.current.song==song and core.meta.current.artist==artist then
      return
    end

    core.meta.last.song      = core.meta.current.song
    core.meta.last.artist    = core.meta.current.artist
    core.meta.current.song   = song
    core.meta.current.artist = artist

    if song and artist then
      vlc.input.item():set_meta('title',  song)
      vlc.input.item():set_meta('artist', artist)

      -- change pidgin message
      if core.pidgin.should_change then
        core:set_pidgin(string.format('%s - %s', song, artist))
      end

      -- now playing, scrobble
      if core.last_fm.authorized then
        if play_count>0 then
          core:scrobbler_scrobble(function(a,b) core:debug(':: scrobble ::') core:debug(a) core:debug(b) end)
        end
        core:scrobbler_now_playing(function(a,b) core:debug(':: now playing ::') core:debug(a) core:debug(b) end)
      end

      play_count = play_count + 1
    end

    core:debug(' meta changed ...')
  end
end

function parse()
  core:debug(' parse')
end

function probe()
  core:debug(' probe')
end

function deactivate()
  if core.pidgin.should_change then
    core:set_pidgin_defaults()
  end
  core:unload()
  core:debug(' deactive')
end

function close()
  core:debug(' close')
  vlc.deactivate()
end