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

-- High Contrast - Racing Green

-- get the token http://ws.audioscrobbler.com/2.0/?method=auth.gettoken&api_key=71e3c271bf0cb0f938a996628566b546&format=json
--   >> {"token":"5e07d50cbc08171c576a1964a142b835"}

-- get user authorization http://www.last.fm/api/auth/?api_key=xxxxxxxxxxx&token=xxxxxxxx
-- wait for browser to close

-- get session http://www.lastfm.com.br/api/show/auth.getSession

-- session call       = api_keyxxxxxxxxmethodauth.getSessiontokenxxxxxxx
-- api signature call = echo "api_keyxxxxxxxxxxxxmethodauth.getSessiontokenxxxxxxxxxxxxxxmysecret"

-- load libraries

local st, os, io, co, tb, json, utils = 
  require('string'), require('os'), require('io'), require('coroutine'), require('table'), require('json'), require('wrp-utils')

local stations = {
  { name = "Ska",                 url = "http://listen.sky.fm/public1/ska.pls" },
  { name = "Drum & Bass",         url = "http://listen.di.fm/public2/drumandbass.pls" },
  { name = "liquid DnB",          url = "http://listen.di.fm/public2/liquiddnb.pls" },
  { name = "Metal",               url = "http://listen.sky.fm/public1/metal.pls" },
  { name = "Moder Rock",          url = "http://listen.sky.fm/public1/modernrock.pls" },
  { name = "Smooth Jazz",         url = "http://listen.sky.fm/public1/smoothjazz.pls"},
  { name = "Uptempo Smooth Jazz", url = "http://listen.sky.fm/public1/uptemposmoothjazz.pls"},
}

--
local dlg, last_fm, pidgin, auth_state, app =
  nil, nil, nil, false, {}

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
  utils:cfg_load(app)
  --
  dlg     = vlc.dialog("Web Radio")
  last_fm = dlg:add_button((app.last_fm.authorized and "scrobbling" or "scrobble ?"), click_authorize, 1, 1, 1, 1)
  pidgin  = dlg:add_button((app.pidgin.should_change and "notifying" or "notify ?"), click_notify, 2, 1, 1, 1)
  list    = dlg:add_list(1, 3, 4, 1)
  play    = dlg:add_button("Play", click_play, 1, 4, 4, 1)
  -- add stations
  for idx, details in ipairs(stations) do
    list:add_value(details.name, idx)
  end

  utils:get_pidgin_defaults(app.pidgin)

  utils:debug("activate")
  utils:debug(app)
  dlg:show()
end

-- *********************
-- Authorization Process
-- *********************
-- check if user authorized this app
function auth_callback(data, msg)
  utils:debug("authorized?")
  utils:debug(data)
  if not data then
    utils:debug('no data in authorization callback')
    app.last_fm.authorized = false
    auth_state             = false
    return
  end

  if data.error then
    utils:debug('error in authorization callback ... '..data.error)
    if data.error==4 or data.error==15 or data.error==14 then
      app.last_fm.token = ''
      auth_state        = false
      last_fm:set_text('scrobble ?')
    else
      auth_state = false
    end
    app.last_fm.authorized = false
    return
  end

  if data.session then
    app.last_fm.session.user = data.session.name
    app.last_fm.session.key  = data.session.key
    app.last_fm.authorized   = true
    auth_state               = true
    last_fm:set_text('scrobbling')
  end
end

-- token callback
function token_callback(data, msg)
  if not data or data.error then
    app.last_fm.token = ''
    auth_state        = false
    last_fm:set_text('scrobble ?')
    return
  end

  os.execute(
    st.format(
      'exec $(which firefox || which google-chrome || which chromium-browser) "%s?api_key=%s&token=%s">/dev/null & echo $!',
      app.last_fm.auth_point,
      app.last_fm.key,
      data.token
    )
  )

  app.last_fm.token = data.token
  auth_state        = false
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
  utils:debug('clicked')
end

function click_notify()
  app.pidgin.should_change = true
  pidgin:set_text("notifying")
end

function click_authorize()
  utils:debug('click_authorize')
  utils:debug(auth_state, app.last_fm.token)
  if auth_state then
    utils:debug('auth_state')
    return
  end  

  if app.last_fm.token~='' then
    -- next stage, check if user autorized
    utils:debug('next stage, check if user autorized')
    auth_state = true
    utils:fetch(
        st.format(
            "%s?method=%s&api_key=%s&api_sig=%s&token=%s&format=%s",
            app.last_fm.base_point,
            'auth.getSession',
            app.last_fm.key,
            utils:md5(
                st.format(
                    "api_key%smethodauth.getSessiontoken%s%s",
                    app.last_fm.key,
                    app.last_fm.token,
                    app.last_fm.secret
                  )
              ),
            app.last_fm.token,
            'json'
          ), 
        auth_callback
      )
  elseif not auth_state and app.last_fm.token=='' then
    -- fetch token
    utils:debug('fetch token')
    auth_state = true
    utils:fetch(
      st.format(
          "%s?method=%s&api_key=%s&format=%s", 
            app.last_fm.base_point,
            'auth.gettoken',
            app.last_fm.key, 
            'json'
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
    
    artist, song = st.match(metas.now_playing, "%s*(.-)%s+%-%s+(.-)%s*$")
    if not artist or not song then
      artist, song = st.match(metas.now_playing, "%s*(.-)%s*%-%s*(.-)%s*$")
    end

    if app.meta.current.song==song and app.meta.current.artist==artist then
      return
    end

    app.meta.last.song      = app.meta.current.song
    app.meta.last.artist    = app.meta.current.artist
    app.meta.current.song   = song
    app.meta.current.artist = artist

    if song and artist then
      vlc.input.item():set_meta('title',  song)
      vlc.input.item():set_meta('artist', artist)

      -- change pidgin message
      if app.pidgin.should_change then
        utils:set_pidgin(st.format('%s - %s', song, artist))
      end

      -- now playing, scrobble
      if app.last_fm.authorized then
        local now_playing_signature = utils:md5(
                st.format(
                    "api_key%sartist%smethodtrack.updateNowPlayingsk%strack%s%s",
                    app.last_fm.key,
                    utils:escape(artist),
                    app.last_fm.session.key,
                    utils:escape(song),
                    app.last_fm.secret
                  )
              )

        --
        local to_send = st.format(
              "curl -X POST %s?method=track.updateNowPlaying&api_key=%s&track=%s&artist=%s" ..
                "&format=json&sk=%s&api_sig=%s",
              app.last_fm.base_point,
              app.last_fm.key,
              utils:escape(song),
              utils:escape(artist),
              app.last_fm.session.key,
              now_playing_signature
            )
        utils:debug(to_send)
        os.execute(to_send)
      end
    end

    utils:debug(' meta changed ...')
  end
end

function parse()
  utils:debug(' parse')
end

function probe()
  utils:debug(' probe')
end

function deactivate()
  if app.pidgin.should_change then
    utils:set_pidgin_defaults(app.pidgin)
  end
  utils:cfg_save(app)
  utils:debug(' deactive')
end

function close()
  utils:debug(' close')
  vlc.deactivate()
end