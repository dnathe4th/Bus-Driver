Bot = require 'ttapi'
irc = require 'irc'
_un = require 'underscore'
util = require 'util'

Db = require('mongodb').Db
Connection = require('mongodb').Connection
Server = require('mongodb').Server

db = new Db 'party-bus', new Server('localhost', 27017, {})

db_connection = null
db.open (error, db)->
  db_connection = db

busDriver = (userAuth, selfId, roomId, ircServer, ircChan, ircHandle="BusDriver") ->
  if not userAuth
    util.puts("User auth token required")
    util.exit
  
  if not selfId
    util.puts("User id token required")
    util.exit
  
  if not roomId
    util.puts("Room id token required")
    util.exit
  
  ircServer = arguments[3]
  ircChan = arguments[4]
  ircHandle = arguments[5] or "BusDriver"
  
  bot = new Bot userAuth, selfId, roomId

  ircClient = new irc.Client ircServer, ircHandle, 
    channels: [ircChan]

  DJ_MAX_SONGS = 3
  
  # How much tolerance we have before we just escort
  DJ_MAX_PLUS_SONGS = 2
  
  DJ_WAIT_SONGS = 3
  
  # Minimum number of DJs to activate reup modding
  MODERATE_DJ_MIN = 3
  
  songName = ""
  upVotes = 0
  downVotes = 0
  lastScore = ""
  roomUsernames = {}
  roomUsers = {}
  active = {}
  roomUsersLeft = {}
  joinedUsers = {}
  joinedTimeout = null
  JOINED_DELAY = 15000
  djSongCount = {}
  campingDjs = {}
  mods = {}
  vips = {}
  lastDj = undefined
  queueEnabled = false
  selfModerator = false
  busDriver.commands = []
  lastDj = undefined
  
  pastDjSongCount = {}
  
  plural = (count) ->
    if count == 1
      's'
    else
      ''
  
  random_select = (list) ->
    list[Math.floor(Math.random()*list.length)]
  
  # Count songs DJs have waited for
  djWaitCount = {}
  
  is_mod = (userId) ->
    userId of mods

  bot.on "update_votes", (data)->
    upVotes = data.room.metadata.upvotes
    downVotes = data.room.metadata.downvotes

    if songName is ""
      bot.roomInfo (data)->
        songName = data.room.metadata.current_song.metadata.song

  bot.on "newsong", (data)->
    if songName isnt ""
        bot.speak "#{songName} - [#{upVotes}] Awesomes, [#{downVotes}] Lames"
        lastScore = "#{songName} - [#{upVotes}] Awesomes, [#{downVotes}] Lames"
    
    # Reset vote count
    upVotes = data.room.metadata.upvotes
    downVotes = data.room.metadata.downvotes
    
    songName = data.room.metadata.current_song.metadata.song
    currentDjId = data.room.metadata.current_dj
    currentDjName = roomUsers[currentDjId]

    if data.room.metadata.current_dj in _un.keys djSongCount
      djSongCount[currentDjId]++
    else
      djSongCount[currentDjId] = 1

    # Only mod if there are some minimum amount of DJs
    if _un.keys(djSongCount).length >= MODERATE_DJ_MIN
      escorted = {}
      
      # Escort DJs that haven't gotten off!
      for djId in _un.keys(campingDjs)
        campingDjs[djId]++
        
        if selfModerator and campingDjs[djId] >= DJ_MAX_PLUS_SONGS
          # Escort off stage
          bot.remDj(djId)
          escorted[djId] = true
      
      if lastDj and not (lastDj.userid of escorted) and not (lastDj.userid of vips) and djSongCount[lastDj.userid] >= DJ_MAX_SONGS
        bot.speak "#{lastDj.name}, you've played #{djSongCount[lastDj.userid]} songs already! Let somebody else get on the decks!"
        
        if not (lastDj.userid of campingDjs)
          campingDjs[lastDj.userid] = 0
    
    for djId in _un.keys(djWaitCount)
      djWaitCount[djId]++
      
      # Remove from timeout list if the DJ has waited long enough
      if djWaitCount[djId] >= DJ_WAIT_SONGS
        delete djWaitCount[djId]
        delete pastDjSongCount[djId]
    
    # Save DJ id
    lastDj = roomUsers[currentDjId]
  
  # Time to wait before considering a rejoining user to have actually come back
  REJOIN_MESSAGE_WAIT_TIME = 5000

  bot.on "registered", (data) ->
    if data.user[0].userid is selfId
      # We just joined, initialize things
      bot.roomInfo (data) ->
        # Initialize users
        for user in data.users
          roomUsernames[user.name] = user
          roomUsers[user.userid] = user
          active[user.userid] = true
              
          if db_connection
            db_connection.collection 'backup', (err, collection) ->
              collection.insert {roomUsernames}
              collection.insert {roomUsers}
              collection.insert {active}

        # Initialize song
        if data.room.metadata.current_song
          songName = data.room.metadata.current_song.metadata.song
          upVotes = data.room.metadata.upvotes
          downVotes = data.room.metadata.downvotes
        
        # Initialize dj counts
        for djId in data.room.metadata.djs
          djSongCount[djId] = 0
        
        currentDj = data.room.metadata.current_dj
        
        if currentDj and currentDj of roomUsers
          djSongCount[currentDj] = 1
          
          lastDj = roomUsers[currentDj]
        
        # Check if we are moderator
        selfModerator = _un.any(data.room.metadata.moderator_id, (id) -> id is selfId)
        
        for modId in data.room.metadata.moderator_id
          mods[modId] = true
    
    for user in data.user
      roomUsernames[user.name] = user
      roomUsers[user.userid] = user
      active[user.userid] = true

    now = new Date()
    user = data.user[0]
      
    # Only say hello to people that have left more than REJOIN_MESSAGE_WAIT_TIME ago    
    if user.userid isnt selfId and (not roomUsersLeft[user.userid] or now.getTime() - roomUsersLeft[user.userid].getTime() > REJOIN_MESSAGE_WAIT_TIME)
      joinedUsers[user.name] = user
      
      delay = ()->
        users_text = (name for name in _un.keys(joinedUsers)).join(", ")
        
        if users_text is "GalGalOne"
          bot.speak "Everyone greet GalGalOne, the prettiest girl on this PARTY BUS!"
        else if users_text is "vuther"
          bot.speak "Hey, papa vuther is here on the PARTY BUS!"
        else
          bot.speak "Hello #{users_text}, welcome aboard the PARTY BUS!"
        
        joinedUsers = {}
        joinedTimeout = null

      if not joinedTimeout
        joinedTimeout = setTimeout delay, 15000
    
    for user in data.user
      # Double join won't spam
      roomUsersLeft[user.userid] = new Date()
  
  bot.on "deregistered", (data)->
    user = data.user[0]
    delete active[user.userid]
    roomUsersLeft[user.userid] = new Date()
  
  # Add and remove moderator
  bot.on "new_moderator", (data) ->
    if data.success
      if data.userid is selfId
        selfModerator = true
      else
        mods[data.userid] = true
  
  bot.on "rem_moderator", (data) ->
    if data.success
      if data.userid is selfId
        selfModerator = false
      else
        delete mods[data.userid]
  
  # Time if a dj rejoins, to resume their song count. Set to about three songs as default (20 minutes). Also gets reset by waiting, whichever comes first.
  DJ_REUP_TIME = 20 * 60 * 1000

  bot.on "add_dj", (data)->
    djId = data.user[0].userid
    
    if _un.keys(djSongCount).length >= MODERATE_DJ_MIN
      if djId of djWaitCount and not (djId of vips) and djWaitCount[djId] <= DJ_WAIT_SONGS
        waitSongs = DJ_WAIT_SONGS - djWaitCount[djId]
        bot.speak "#{data.user[0].name}, party foul! Wait #{waitSongs} more song#{plural(waitSongs)} before getting on the decks again!"
        
        if selfModerator
          # Escort off stage
          bot.remDj(djId)
    
    now = new Date()
    
    # Resume song count if DJ rejoined too quickly
    if djId of pastDjSongCount and now.getTime() - pastDjSongCount[djId].when.getTime() < DJ_REUP_TIME
      djSongCount[djId] = pastDjSongCount[djId].count
    else
      djSongCount[djId] = 0

  bot.on "rem_dj", (data)->
    djId = data.user[0].userid
    
    # Add to timeout list if DJ has played 
    if djSongCount[djId] >= DJ_MAX_SONGS and not djWaitCount[djId]
      # I believe the new song message is triggered first. Could ignore the message if it is too soon
      djWaitCount[djId] = 0
      
    # TODO consider lineskipping
    pastDjSongCount[djId] = { count: djSongCount[djId], when: new Date() }
    delete djSongCount[djId]
    delete campingDjs[djId]

  ircClient.addListener "message", (from, to, message)->
    # irc handling
    # no custom commands yet
  
  findDj = (name) ->
    if userId = _un.select(_un.keys(djSongCount), (id) -> roomUsers[id] and roomUsers[id].name is name)
      return roomUsers[userId]
  
  # Commands
  cmd_last_song = ->
    if lastScore isnt ""
      bot.speak "The previous song: #{lastScore}"
    else
      bot.speak "I blacked out and forgot what the last song was."
  
  cmd_boot = (user, args) ->
    util.puts ""
  
  cmd_escort = (user, args) ->
    if selfModerator and djUser = findDj(args)
      bot.remDj(djUser.userid)
  
  cmd_vip = (user, args) ->
    if args of roomUsernames
      vipUser = roomUsernames[args]
      
      vips[vipUser.userid] = vipUser
      bot.speak "Party all you want, #{vipUser.name}, because you're now a VIP!"
    else
      bot.speak "I couldn't find #{args} in the bus to make a VIP!"
  
  cmd_unvip = (user, args) ->
    vip = _un.detect(vips, (user, userId) -> user.name is args)
    
    if vip
      bot.speak "#{vip.name} is no longer special"
      delete vips[vip.userid]
    else
      bot.speak "#{args} is not a VIP in the Party Bus!"
  
  cmd_vips = ->
    if _un.keys(vips).length > 0
      vip_list = (vipUser.name for vipId, vipUser of vips).join(", ")
      bot.speak "Current VIPs in the Party Bus are #{vip_list}"
    else
      bot.speak "There are no VIPs in the Party Bus right now"
  
  cmd_party = ->
    bot.speak "AWWWWWW YEAHHHHHHH!"
    bot.speak "/me dances"
    bot.vote "up"
  
  cmd_dance = -> 
    bot.speak "THIS IS MY JAM!"
    bot.speak "/me dances"
    bot.vote "up"
  
  cmd_djs = ->
    if _un.keys(djSongCount).length == 0
      bot.speak "I don't have enough info yet for a song count"
    else
      out = "Song Totals: "
      for dj in _un.keys(djSongCount)
        out += "#{roomUsers[dj].name}: #{djSongCount[dj]}, "
      bot.speak out.substring 0, out.length-2

  cmd_mods = ->
    bot.roomInfo (data) ->        
      # Collect mods
      mod_list = (roomUsers[modId].name for modId in data.room.metadata.moderator_id when active[modId] and modId isnt selfId).join(", ")
      bot.speak "Current mods in the Party Bus are #{mod_list}"
  
  cmd_users = ->
    bot.roomInfo (data) ->
      count = _un.keys(data.users).length
      bot.speak "There are #{count} peeps rocking the Party Bus right now!"
  
  cmd_help = (user, args) ->
    bot.speak "Hey #{user.name}, welcome aboard the party bus. It's FFA, 3 song limit, 3 song wait time. No autoclickers! Get a list of commands with /commands"
  
  cmd_commands = ->
    cmds = _un.select(busDriver.commands, (entry) -> not entry.hidden and not entry.mod)
    cmds_text = _un.map(cmds, (entry) -> entry.name or entry.cmd).join(", ")
    
    bot.speak cmds_text
  
  cmd_waiting = ->
    if _un.keys(djWaitCount).length == 0
      bot.speak "No DJs are on the timeout list!"
    else
      waiting_list = ("#{roomUsers[djId].name} - #{DJ_WAIT_SONGS - count}" for djId, count of djWaitCount).join(", ")
      bot.speak "DJ timeout list: #{waiting_list}"
  
  cmd_queue = (user, args) ->
    if not queueEnabled
      bot.speak "#{user.name}, the Party Bus has no queue! It's FFA, #{DJ_MAX_SONGS} song limit, #{DJ_WAIT_SONGS} song wait time"
  
  cmd_queue_add = (user, args) ->
    if not queueEnabled
      bot.speak "#{user.name}, the Party Bus has no queue! It's FFA, #{DJ_MAX_SONGS} song limit, #{DJ_WAIT_SONGS} song wait time"
  
  cmd_vuthers = ->
    bot.roomInfo (data) ->
      vuther_pat = /\bv[aeiou]+\w*th[aeiou]\w*r\b/i
      
      daddy = false
      
      is_vutherbot = (name) ->
        if name is "vuther"
          daddy = true
          return false
        else
          return vuther_pat.test(name)
      
      vuthers = _un.select(data.users, (user) -> is_vutherbot(user.name))
      vuthers = _un.map(vuthers, (user) -> user.name)
      
      msg = "vuther force, assemble!"
      
      if vuthers.length > 0
        msg += " There are #{vuthers.length} vuthers here: " + vuthers.join(", ") + "."
      else
        msg += " There are no vuthers here..."
      
      if daddy
        if vuthers.length > 0
          msg += " And daddy vuther is here!"
        else
          msg += " But daddy vuther is here!"
      
      bot.speak msg
  
  cmd_setsongs = (user, args) ->
    setsongs_pat = /^(.+?)\s+(-?\d+)\s*$/
    
    if match = setsongs_pat.exec(args)
      name = match[1]
      count = parseInt(match[2])
      
      if djUser = findDj(name)
        djSongCount[djUser.userid] = count
        
        # Set camping if over
        if count >= DJ_MAX_SONGS and not (djUser.userid of campingDjs)
          campingDjs[djUser.userid] = 0
        
        # Remove camping if under
        if count < DJ_MAX_SONGS and djUser.userid of campingDjs
          delete campingDjs[djUser.userid]
  
  cmd_resetdj = (user, args) ->
    djUser = _un.detect(roomUsers, (user, userId) -> user.name is args)
    
    if djUser
      if djUser.userid of djSongCount
        djSongCount[djUser.userid] = 0
      
      delete campingDjs[djUser.userid]
      delete djWaitCount[djUser.userid]  
  
  # TODO, match regexes, and have a hidden, so commands automatically lists
  commands = [
    {cmd: "/last_song", fn: cmd_last_song, help: "votes for the last song"}
    {cmd: "/party", fn: cmd_party, help: "party!"}
    {cmd: "/dance", fn: cmd_dance, help: "dance!"}
    {cmd: "/djs", fn: cmd_djs, help: "dj song count"}
    {cmd: "/mods", fn: cmd_mods, help: "lists room mods"}
    {cmd: "/users", fn: cmd_users, help: "counts room users"}
    {cmd: /^\/(timeout|waiting|waitlist)$/, name: "/timeout", fn: cmd_waiting, help: "dj timeout list"}
    {cmd: "/vuthers", fn: cmd_vuthers, help: "vuther clan roll call"}
    {cmd: /^\/(help|\?)$/, name: "/help", fn: cmd_help, help: "get help"}
    {cmd: "/commands", fn: cmd_commands, help: "get list of commands"}
    {cmd: /^(q|\/q(ueue)?|q\?)$/, name: "/queue", fn: cmd_queue, hidden: true, help: "get dj queue info"}
    {cmd: "q+", fn: cmd_queue_add, hidden: true, help: "add to dj queue"}
    {cmd: "/vips", fn: cmd_vips, help: "list vips"}
    {cmd: "/vip", fn: cmd_vip, mod: true, help: "make user a vip (no limit)"}
    {cmd: "/unvip", fn: cmd_unvip, mod: true, help: "remove vip status"}
    {cmd: "/setsongs", fn: cmd_setsongs, mod: true, help: "set song count"}
    {cmd: "/reset", fn: cmd_resetdj, mod: true, help: "reset song count for djs"}
    {cmd: "/escort", fn: cmd_escort, mod: true, help: "escort a dj"}
  ]
  
  busDriver.commands = commands
  
  command = (data) ->
    cmd_pat = /^([^\s]+?)(\s+([^\s]+.+?))?\s*$/
    
    cmd = ""
    args = ""
    
    if match = cmd_pat.exec(data.text)
      cmd = match[1].toLowerCase()
      args = match[3] or ""
    
    [cmd, args]
  
  bot.on "speak", (data) ->
    [cmd_txt, args] = command(data)
    user = roomUsers[data.userid]
    
    cmd_matches = (entry) ->
      if typeof entry.cmd == "string" and entry.cmd is cmd_txt
        return true
      if typeof entry.cmd == "function" and entry.cmd.test(cmd_txt)
        return true
    
    resolved_cmd = _un.detect(commands, cmd_matches)
    
    if resolved_cmd
      if not resolved_cmd.mod or (resolved_cmd.mod and is_mod(data.userid))
        resolved_cmd.fn(user, args)
  
exports.busDriver = busDriver