
Minerva Syncer
==============

This is a bash script, which utilizes curl, to sync a local folder
with the documents on [Minerva](http://minerva.ugent.be).
Automatically downloads new files, ask to update changed files, ...

Anyone who finds bugs and stuff, please tell me about them. Do not
fear testing, I've written no computer/Minerva breaking code.

Notes
-----

Currently, all the script does is creating a file structure in the
`./Minerva/.minerva` directory. Later, the actual files will be moved
to the `./Minerva` directory (which you can specify in a config file
etc).
