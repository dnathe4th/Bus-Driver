# Description
Bus Driver is a bot for www.turntable.fm that adds functionality to The Party Bus room.

This bot heavily relies on Alain's TTAPI - https://github.com/alaingilbert/Turntable-API

# Usage
This module is NOT on npm yet. Clone this repo locally to use the bot.
IRC and TurnTable credentials must be supplied.

## Warning
This bot does not work on the latest release of `NodeJs (v0.5.8)`. It is tested and works on `NodeJs (v.0.4.8)`

## Example

In a file in the same folder as the cloned repository (you can copy and rename `controller.coffee.example`):

	busdriver = require "./busdriver"

	userAuth = "auth+live+FILL IN AUTH TOKEN HERE"
	userId = "FILL IN USER ID HERE"
	roomId = "FILL IN ROOM ID HERE"
	ircServer = "irc.HOST.TDL"
	ircChan = "#THISISACHANIJUSTMADEUP"
	ircHandle = "BusDriver"

	owners = [
		"OWNER USER ID"
		"OWNER 2 USER ID"
	]

	driver = new busdriver.busDriver userAuth, userId, roomId, owners, ircServer, ircChan, ircHandle

Compile `busdriver` and the `controller` from `CoffeeScript` into `JavaScript` and run with `Node`

# Call to Action
PLEASE Fork this and make some pull requests if you feel so inclined!
