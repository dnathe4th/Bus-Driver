Bot = require 'ttapi'
irc = require 'irc'
_un = require 'underscore'


busDriver= ()->
  userAuth = arguments[0]
  userId = arguments[1]
  roomId = arguments[2]
  ircServer = arguments[3]
  ircChan = arguments[4]

  bot = new Bot userAuth, userId, roomId

  ircClient = new irc.Client ircServer, "BusDriver", 
    channels: [ircChan]


  songName = ""
  upVotes = 0
  downVotes = 0
  lastScore = ""
  roomUsers = {}
  djSongCount = {}

  command = (data)->
    data.text.toLowerCase().split(" ")[0]

  bot.on "update_votes", (data)=>
    upVotes = data.room.metadata.upvotes
    downVotes = data.room.metadata.downvotes

    if songName is ""
      bot.roomInfo (data)=>
        songName = data.room.metadata.current_song.metadata.song

  bot.on "newsong", (data)=>
    if songName isnt ""
        bot.speak "#{songName} - [#{upVotes}] Awesomes, [#{downVotes}] Lames"
        lastScore = "#{songName} - [#{upVotes}] Awesomes, [#{downVotes}] Lames"

    songName = data.room.metadata.current_song.metadata.song

    if data.room.metadata.current_dj in _un.keys djSongCount
      djSongCount[data.room.metadata.current_dj]++
    else
      djSongCount[data.room.metadata.current_dj] = 1

  bot.on "registered", (data)=>
    if data.user[0].name is "Bus Driver" # init stuff
      bot.roomInfo (data)=>
        for user in data.users
          roomUsers[user.name] = user
          roomUsers[user.userid] = user
    for user in data.user
      roomUsers[user.name] = user
      roomUsers[user.userid] = user

    delay = ()->
      if data.user[0].name isnt "Bus Driver" and data.user[0].name isnt "GalGalOne"
        bot.speak "Hello #{data.user[0].name}, welcome on board the PARTY BUS!"
      if data.user[0].name is "GalGalOne"
        bot.speak "Everyone greet GalGalOne, the prettiest girl on this PARTY BUS!"

    setTimeout delay, 1000

  bot.on "add_dj", (data)=>
    djSongCount[data.user[0].userid] = 0

  bot.on "rem_dj", (data)=>
    delete djSongCount[data.user[0].userid]

  ircClient.addListener "message", (from, to, message)=>
    # irc handling
    # no custom commands yet

  bot.on "speak", (data)=>
    if command(data) is "/previous_song" or command(data) is "/last_song"
      if lastScore isnt ""
        bot.speak "The previous song: #{lastScore}"

    if command(data) is "/dance"
      bot.speak "THIS IS MY JAM!"
      bot.speak "/me dances"
      bot.vote "up"
      
      if command(data) is "/party"
      bot.speak "AWWWWWW YEAHHHH!!!!!!"
      bot.speak "/me dances"
      bot.vote "up"

    if command(data) is "/djs"
      if _un.keys(djSongCount).length < 5
        bot.speak "I don't have enough info yet for a song count"
      else
        out = "Song Totals: "
        for dj in _un.keys(djSongCount)
          out += "#{roomUsers[dj].name}: #{djSongCount[dj]}, "
        bot.speak out.substring 0, out.length-2

exports.busDriver = busDriver