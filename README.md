# Description
Bus Driver is a bot for www.turntable.fm that adds functionality to The Party Bus room.

This bot heavily relies on Alain's TTAPI - https://github.com/alaingilbert/Turntable-API

# Usage
This module is NOT on npm yet. Clone this repo locally to use the bot.
IRC and TurnTable credentials must be supplied.

## Warning
This bot does not work on the latest release of `NodeJs (v0.5.8)`. It is tested and works on `NodeJs (v.0.4.8)`

## Example

		busdriver = require "./busdriver"

		userAuth = "auth+live+99999999999999999999999"
		userId = "LOLOMGJKIWANNADJHAHAWTF"
		roomId = 'GOFINDYOUROWNROOM'
		ircServer = 'irc.HOST.TDL'
		ircChan = "#THISISACHANIJUSTMADEUP"

		driver = new busdriver.busDriver userAuth, userId, roomId, ircServer, ircChan

# Call to Action
PLEASE Fork this and make some pull requests if you feel so inclined!
