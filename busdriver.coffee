Bot = require 'ttapi'
irc = require 'irc'
_un = require 'underscore'

userAuth = "auth+live+c399d02ac41ccf4d2d3bfa38b130741e516455dd"
userId = "4ea23043a3f75174a5098a8b"
roomId = '4e9e8e5514169c0cb91bc11a'
ircServer = 'irc.freenode.net'
ircChan = "#tmp_tt_bot_controller"

bot = new Bot userAuth, userId, roomId

ircClient = new irc.Client ircServer, "BusDriver", 
  channels: [ircChan]


songName = ""
upVotes = 0
downVotes = 0


bot.on "speak", (data)=>
  #  @bot.vote("up")      

bot.on "update_votes", (data)=>
  upVotes = data.room.metadata.upvotes
  downVotes = data.room.metadata.downvotes

bot.on "newsong", (data)=>
  if songName isnt ""
      bot.speak "#{songName} - [#{upVotes}] Awesomes, [#{downVotes}] Lames"

  songName = data.room.metadata.current_song.metadata.song

ircClient.addListener "message", (from, to, message)=>
  # irc handling
