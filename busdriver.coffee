Bot = require 'ttapi'
irc = require 'irc'
_un = require 'underscore'
util = require 'util'
readline = require 'readline'

busDriver = (options) ->
  if not options.userAuth
    util.puts("User auth token required")
    util.exit
  
  if not options.userId
    util.puts("User id token required")
    util.exit
  
  if not options.roomId
    util.puts("Room id token required")
    util.exit
  
  bot = new Bot options.userAuth, options.userId, options.roomId

  options.excluded_mods = options.excluded_mods or []
  options.ircHandle = options.ircHandle or "BusDriver"
  selfId = options.userId
  
  ircClient = new irc.Client options.ircServer, options.ircHandle, 
    channels: [options.ircChan]

  DJ_MAX_SONGS = 3
  
  # How much tolerance we have before we just escort
  DJ_MAX_PLUS_SONGS = 2
  
  DJ_WAIT_SONGS = 3
  DJ_WAIT_SONGS_NIGHT = 1
  
  night = false
  
  wait_songs = ->
    if not night
      DJ_WAIT_SONGS
    else
      DJ_WAIT_SONGS_NIGHT
  
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
  lastActivity = {}
  JOINED_DELAY = 15000
  djSongCount = {}
  campingDjs = {}
  mods = {}
  vips = {}
  lastDj = undefined
  queueEnabled = false
  selfModerator = false
  busDriver.commands = []
  permabanned = {}
  enabled = true
  debug_on = false
  
  pastDjSongCount = {}
  
  plural = (count) ->
    if count == 1
      's'
    else
      ''
  
  random_select = (list) ->
    list[Math.floor(Math.random()*list.length)]
  
  debug = (txt) ->
    if debug_on
      util.puts txt
  
  # Count songs DJs have waited for
  djWaitCount = {}
  
  is_mod = (userId) ->
    userId of mods
  
  is_owner = (userId) ->
    _un.include(options.owners, userId)

  bot.on "update_votes", (data)->
    upVotes = data.room.metadata.upvotes
    downVotes = data.room.metadata.downvotes

    if songName is ""
      bot.roomInfo (data)->
        songName = data.room.metadata.current_song.metadata.song
    
    # This might work... not sure what the votelog is
    for [userId, vote] in data.room.metadata.votelog
      update_idle(userId)

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
    if enabled and _un.keys(djSongCount).length >= MODERATE_DJ_MIN
      escorted = {}
      
      # Escort DJs that haven't gotten off!
      for dj in _un.keys(campingDjs)
        campingDjs[dj]++
        
        if selfModerator and campingDjs[dj] >= DJ_MAX_PLUS_SONGS
          # Escort off stage
          bot.remDj(dj)
          escorted[dj] = true
      
      if lastDj and not (lastDj of escorted) and not (lastDj of vips) and djSongCount[lastDj] >= DJ_MAX_SONGS
        bot.speak "#{roomUsers[lastDj].name}, you've played #{djSongCount[lastDj]} songs already! Let somebody else get on the decks!"
        
        if not (lastDj of campingDjs)
          campingDjs[lastDj] = 0
    
    for dj in _un.keys(djWaitCount)
      djWaitCount[dj]++
      
      # Remove from timeout list if the DJ has waited long enough
      if djWaitCount[dj] >= wait_songs()
        delete djWaitCount[dj]
        delete pastDjSongCount[dj]
    
    # Save DJ id
    lastDj = currentDjId
  
  # Time to wait before considering a rejoining user to have actually come back
  REJOIN_MESSAGE_WAIT_TIME = 5000

  greetings =
    ".Mnml_Pixels": "/me awkwardly hugs .Mnml_Pixels"
    "Cameronish": "/me daps C Murda'"
    "DJ Wooooo": "This party must really be poppin', DJ Wooooo is in the house!"
    "Elletiger": "Watch out, Elletiger is on the prowl!"
    "Frick": "SCATTER! It's bot overlord Frick!"
    "GalGal": "Everyone greet GalGal, the prettiest girl on this PARTY BUS!"
    "icyhandofcrap": "What is your command, master icy?"
    "IT'S OVER 9000!!!!": "Vegeta, what does the scouter say about his power level? It's OVER 9000!!!!"
    "Jellytime": "It's peanut butter JELLYTIME!"
    "Nick The K": "Hey, I think Nick The K is AFK!"
    "sex": "Who wants sex?"
    "vuther": "Hey, papa vuther is here on the PARTY BUS!"
  
  norm = (name) ->
    name.trim().toLowerCase()
  
  update_name = (name, uid) ->
    roomUsernames[norm(name)] = uid
  
  update_idle = (uid) ->
    lastActivity[uid] = (new Date()).getTime()
  
  named_user = (name) ->
    name = norm(name)
    if name of roomUsernames
      roomUsers[roomUsernames[name]]
  
  get_uid = (name) ->
    roomUsernames[norm(name)]
  
  bot.on "registered", (data) ->
    if data.user[0].userid is selfId
      # We just joined, initialize things
      bot.roomInfo (data) ->
        # Initialize users
        for user in data.users
          update_name(user.name, user.userid)
          roomUsers[user.userid] = user
          active[user.userid] = true
          update_idle(user.userid)
        
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
      update_name(user.name, user.userid)
      roomUsers[user.userid] = user
      active[user.userid] = true
      update_idle[user.userid]

    now = new Date()
    user = data.user[0]
    
    if user.userid of permabanned
      if selfModerator
        bot.bootUser(user.userid, permabanned[user.userid])
        return
      else
        bot.speak "I can't boot you, #{user.name}, but you've been banned for #{permabanned[user.userid]}"
      
    # Only say hello to people that have left more than REJOIN_MESSAGE_WAIT_TIME ago    
    if user.userid isnt selfId and (not roomUsersLeft[user.userid] or now.getTime() - roomUsersLeft[user.userid].getTime() > REJOIN_MESSAGE_WAIT_TIME)
      if user.userid of vips
        delay = ()->
          bot.speak "Welcome #{user.name}, we have a VIP aboard the PARTY BUS!"

        setTimeout delay, 5000
      else if user.name of greetings
        delay = ()->
          bot.speak greetings[user.name]

        setTimeout delay, 5000
      else if user.acl > 0
        delay = ()->
          bot.speak "We have a superuser in the HOUSE! #{user.name}, welcome aboard the PARTY BUS!"

        setTimeout delay, 5000
      else
        joinedUsers[user.name] = user
        
        delay = ()->
          users_text = (name for name in _un.keys(joinedUsers)).join(", ")
          
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
    update_name(data.user[0].name, data.user[0].userid)
    djId = data.user[0].userid
    
    if enabled and _un.keys(djSongCount).length >= MODERATE_DJ_MIN
      if djId of djWaitCount and not (djId of vips) and djWaitCount[djId] <= wait_songs()
        waitSongs = wait_songs() - djWaitCount[djId]
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
    if enabled and djSongCount[djId] >= DJ_MAX_SONGS and not djWaitCount[djId]
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
    uid = get_uid(name)
    if uid of djSongCount
      return uid
    
  countdown = (callback, it, time) ->
    if time > 0
      it(time)
      delay = -> countdown(callback, it, time-1)
      setTimeout(delay, 1000)
    else
      callback()
  
  delay_countdown = (callback, it, time) ->
    delay = -> countdown(callback, it, time)
    
    setTimeout(delay, 1000)
  
  # Commands
  cmd_last_song = ->
    if lastScore isnt ""
      bot.speak "The previous song: #{lastScore}"
    else
      bot.speak "I blacked out and forgot what the last song was."
  
  cmd_boot = (user, args) ->
    if selfModerator
      boot_pat = /^\s*(.*?)\s*:\s*([^\s].+?)\s*$/
      
      if match = boot_pat.exec(args)
        name = match[1]
        reason = match[2]
        
        bot.roomInfo (data) ->
          if uid = get_uid(name)
            if uid is options.userId
              bot.speak "I'm not booting myself!"
            else
              bot.bootUser(uid, reason)
          else
            bot.speak "I couldn't find #{name} to boot!"
      else
        bot.speak "#{user.name} you have to give a reason to boot!"
    else
      bot.speak "I'm powerless, do it yourself!"
  
  cmd_escort = (user, args) ->
    if selfModerator
      if dj = findDj(args)
        bot.remDj(dj)
    else
      bot.speak "I'm powerless, do it yourself!"
  
  cmd_vip = (user, args) ->
    if vipUser = named_user(args)
      vips[vipUser.userid] = vipUser
      bot.speak "Party all you want, #{vipUser.name}, because you're now a VIP!"
    else
      bot.speak "I couldn't find #{args} in the bus to make a VIP!"
  
  cmd_unvip = (user, args) ->
    vipUser = named_user(args)
    
    if vipUser.userid of vips
      bot.speak "#{vipUser.name} is no longer special"
      delete vips[vipUser.userid]
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
    bot.vote "up"
  
  cmd_dance = -> 
    bot.speak "Erryday I'm Shufflin'"
    bot.vote "up"
  
  cmd_djs = (user, args, out) ->
    if _un.keys(djSongCount).length == 0
      out "I don't have enough info yet for a song count"
    else
      txt = "Song Totals: "
      bot.roomInfo (data) ->
        newDjSongCount = {}
        
        for dj in data.room.metadata.djs
          newDjSongCount[dj] = djSongCount[dj] or 0
        
        djSongCount = newDjSongCount
        
        out (txt + ("#{roomUsers[dj].name}: #{count}" for dj, count of djSongCount).join(", "))

  cmd_mods = ->
    bot.roomInfo (data) ->
      # Collect mods
      mod_list = (roomUsers[modId].name for modId in data.room.metadata.moderator_id when active[modId] and modId isnt selfId and not (modId in options.excluded_mods)).join(", ")
      bot.speak "Current mods in the Party Bus are #{mod_list}"
  
  cmd_users = ->
    bot.roomInfo (data) ->
      count = _un.keys(data.users).length
      bot.speak "There are #{count} peeps rocking the Party Bus right now!"
  
  cmd_help = (user, args) ->
    bot.speak "Hey #{user.name}, welcome aboard the party bus. Read the room rules: http://bit.ly/partyrules"
  
  cmd_hidden = (cmd) ->
    cmd.hidden or cmd.owner or cmd.mod
  
  cmd_commands = ->
    cmds = _un.select(busDriver.commands, (cmd) -> not cmd_hidden(cmd))
    cmds_text = _un.map(cmds, (entry) -> entry.name or entry.cmd).join(", ")
    
    bot.speak cmds_text
  
  cmd_waiting = ->
    if _un.keys(djWaitCount).length == 0
      bot.speak "No DJs are in the naughty corner!"
    else
      waiting_list = ("#{roomUsers[dj].name}: #{wait_songs() - count}" for dj, count of djWaitCount).join(", ") + " songs"
      bot.speak "DJ naughty corner: #{waiting_list}"
  
  cmd_queue = (user, args) ->
    if not queueEnabled
      bot.speak "#{user.name}, the Party Bus has no queue! It's FFA, #{DJ_MAX_SONGS} song limit, #{DJ_WAIT_SONGS} song wait time"
  
  cmd_queue_add = (user, args) ->
    if not queueEnabled
      bot.speak "#{user.name}, the Party Bus has no queue! It's FFA, #{DJ_MAX_SONGS} song limit, #{DJ_WAIT_SONGS} song wait time"
  
  cmd_vuthers = ->
    bot.roomInfo (data) ->
      vuther_pat = /\bv[aeiou]+\w*th[aeiou]\w*r/i
      
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
      
      if dj = findDj(name)
        djSongCount[dj] = count
        
        # Set camping if over
        if count >= DJ_MAX_SONGS and not (dj of campingDjs)
          campingDjs[dj] = 0
        
        # Remove camping if under
        if count < DJ_MAX_SONGS and dj of campingDjs
          delete campingDjs[dj]
  
  cmd_resetdj = (user, args) ->
    if djUser = named_user(args)
      if djUser.userid of djSongCount
        djSongCount[djUser.userid] = 0
      
      delete campingDjs[djUser.userid]
      delete djWaitCount[djUser.userid] 
  
  cmd_off = ->
    enabled = false
    bot.speak "Party all you want, because DJ limits are off!"
  
  cmd_on = ->
    enabled = true
    bot.speak "DJ limits are enabled again"
  
  cmd_uid = (user, args, out) ->
    if user = named_user(args)
      out user.userid
  
  cmd_permaban = (user, args) ->
    boot_pat = /^\s*(.*?)\s*:\s*([^\s].+?)\s*$/
    
    if match = boot_pat.exec(args)
      name = match[1]
      reason = match[2]
    
      if user = named_user(name)
        if user.userid is options.userId
          bot.speak "I'm not booting myself!"
        else
          if selfModerator
            bot.bootUser(user.userid, reason)
            bot.speak "Banning #{roomUsers[user.userid].name}"
          else
            bot.speak "I'm powerless to ban anyone, but #{roomUsers[user.userid].name} is on the list!"
                  
          permabanned[user.userid] = reason
  
  cmd_unpermaban = (user, args) ->
    name = args.toLowerCase()
    
    if name of permabanned
      delete permabanned[name]
      bot.speak "Unbanning #{roomUsers[name].name}"
    else if user = named_user(name)
      delete permabanned[user.userid]
      bot.speak "Unbanning #{roomUsers[user.userid].name}"
  
  cmd_chinesefiredrill = (user, args) ->
    bot.roomInfo (data) ->
      if selfModerator and args is "THIS IS ONLY A DRILL"
        bot.speak "CHINESE FIRE DRILL! In 3"
        
        callback = ->
          for djId in data.room.metadata.djs
            bot.remDj(djId)
          bot.bootUser(user.userid, "for pulling the fire alarm")
        
        it = (i) -> bot.speak(i)
        delay_countdown(callback, it, 2)
      else
        bot.speak "CHINESE FIRE DRILL DRILL! In 3"
        
        msg = -> bot.speak "Escorting " + (roomUsers[dj].name for dj in data.room.metadata.djs).join(", ") + " and booting #{user.name} for pulling the fire alarm."
        it = (i) -> bot.speak(i)
        delay_countdown(msg, it, 2)
        
  
  cmd_power = (user, args) ->
    bot.roomInfo (data) ->
      name = norm(args)
      
      if name isnt ""
        # Initialize users
        if user = _un.find(data.users, (user) -> norm(user.name) is norm(args))
          power = Math.floor(user.points / 1000)
          if power > 0
            bot.speak "Vegeta, what does the scouter say about #{user.name}'s power level? It's over #{power}000!!!"
          else
            bot.speak "#{user.name} doesn't have much of a power level..."
        else
          bot.speak "The scouter couldn't find anyone named #{args}!"
      else
        bot.speak "Who?"
  
  cmd_night = ->
    night = true
    bot.speak "It's late at night! DJs wait #{DJ_WAIT_SONGS_NIGHT} songs"
    
    for dj, count of djWaitCount
      if count > DJ_WAIT_SONGS_NIGHT
        delete djWaitCount[dj]
  
  cmd_day = ->
    night = false
    bot.speak "It's bumping in here! DJs wait #{DJ_WAIT_SONGS} songs"
  
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
    {cmd: /^\/(help|\?|rules)$/, name: "/help", fn: cmd_help, help: "get help"}
    {cmd: "/commands", fn: cmd_commands, hidden: true, help: "get list of commands"}
    {cmd: /^(q|\/q(ueue)?|q\?)$/, name: "/queue", fn: cmd_queue, hidden: true, help: "get dj queue info"}
    {cmd: "q+", fn: cmd_queue_add, hidden: true, help: "add to dj queue"}
    {cmd: "/power", fn: cmd_power, help: "checks the power level of a user using the scouter"}
    {cmd: "/vips", fn: cmd_vips, help: "list vips"}
    {cmd: "/vip", fn: cmd_vip, owner: true, help: "make user a vip (no limit)"}
    {cmd: "/unvip", fn: cmd_unvip, owner: true, help: "remove vip status"}
    {cmd: "/setsongs", fn: cmd_setsongs, owner: true, help: "set song count"}
    {cmd: "/reset", fn: cmd_resetdj, owner: true, help: "reset song count for djs"}
    {cmd: "/escort", fn: cmd_escort, mod: true, help: "escort a dj"}
    {cmd: "/boot", fn: cmd_boot, mod: true, help: "boot a user"}
    {cmd: "/on", fn: cmd_on, owner: true, help: "turn on dj limits"}
    {cmd: "/off", fn: cmd_off, owner: true, help: "turn off dj limits"}
    {cmd: "/uid", fn: cmd_uid, owner: true, help: "get user id"}
    {cmd: "/permaban", fn: cmd_permaban, owner: true, help: "ban a user"}
    {cmd: "/unpermaban", fn: cmd_unpermaban, owner: true, help: "unban a user"}
    {cmd: "/night", fn: cmd_night, owner: true, help: "night mode"}
    {cmd: "/day", fn: cmd_day, mod: true, help: "day mode"}
    {cmd: "/chinesefiredrill", fn: cmd_chinesefiredrill, owner: true, help: "boot everybody off stage. Must type THIS IS ONLY A DRILL :D"}
  ]
  
  busDriver.commands = commands
  
  command = (line) ->
    cmd_pat = /^([^\s]+?)(\s+([^\s]+.+?))?\s*$/
    
    cmd = ""
    args = ""
    
    if match = cmd_pat.exec(line)
      cmd = match[1].toLowerCase()
      args = match[3] or ""
    
    [cmd, args]
  
  cmd_allowed = (user, cmd) ->
    is_owner(user.userid) or (not cmd.owner and (is_mod(user.userid) or not cmd.mod))
  
  cmd_logged = (cmd) ->
    cmd.owner or cmd.mod
  
  cmd_debug = (user, args) ->
    arg = norm(args)
    if arg is "true" or arg is "on"
      util.puts "Debug mode enabled!"
      debug_on = true
    else
      util.puts "Debug mode OFF"
      debug_on = false
  
  cli_commands = [
    {cmd: "/vip", fn: cmd_vip, help: "make user a vip (no limit)"}
    {cmd: "/unvip", fn: cmd_unvip, help: "remove vip status"}
    {cmd: "/setsongs", fn: cmd_setsongs, help: "set song count"}
    {cmd: "/djs", fn: cmd_djs, help: "dj song count"}
    {cmd: "/reset", fn: cmd_resetdj, help: "reset song count for djs"}
    {cmd: "/escort", fn: cmd_escort, help: "escort a dj"}
    {cmd: "/boot", fn: cmd_boot, help: "boot a user"}
    {cmd: "/on", fn: cmd_on, help: "turn on dj limits"}
    {cmd: "/off", fn: cmd_off, help: "turn off dj limits"}
    {cmd: "/permaban", fn: cmd_permaban, help: "ban a user"}
    {cmd: "/unpermaban", fn: cmd_unpermaban, help: "unban a user"}
    {cmd: "/userid", fn: cmd_uid, help: "get user id"}
    {cmd: "/debug", fn: cmd_debug, help: "enable/disable debug"}
  ]

  rl = readline.createInterface(process.stdin, process.stdout)
  
  rl.on "line", (line) ->
    [cmd_txt, args] = command(line)
      
    cmd_matches = (entry) ->
      if typeof entry.cmd == "string" and entry.cmd is cmd_txt
        return true
      if typeof entry.cmd == "function" and entry.cmd.test(cmd_txt)
        return true
    
    if resolved_cmd = _un.find(commands, cmd_matches)
      user = roomUsers[selfId]
      resolved_cmd.fn(user, args)
  
  rl.on "close", ->
    process.stdout.write '\n'
    process.exit 0
  
  bot.on "speak", (data) ->
    update_name(data.name, data.userid)
    update_idle(data.userid)
    [cmd_txt, args] = command(data.text)
    user = roomUsers[data.userid]
      
    cmd_matches = (entry) ->
      if typeof entry.cmd == "string" and entry.cmd is cmd_txt
        return true
      if typeof entry.cmd == "function" and entry.cmd.test(cmd_txt)
        return true
    
    resolved_cmd = _un.find(commands, cmd_matches)
    
    if resolved_cmd and cmd_allowed(user, resolved_cmd)
      if cmd_logged(resolved_cmd)
        now = new Date()
        util.puts "MOD #{now.toTimeString()}: #{data.name}: #{data.text}"
      resolved_cmd.fn(user, args, (txt) -> bot.speak(txt))
  
exports.busDriver = busDriver
