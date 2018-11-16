# Watch & sYNC

Watch files or directories and sync them to a server. Exclude and size filters can be used too.

Based on the original [Convector](https://github.com/javiergarmon/Convector)

# Dependencies:

* rsync
* inotifywait

# Ignore files

If a _.wyncignore_ file is found while traversing directories, it is read and every line inside it excluded from sync.
If a _.wyndirignore_ file is found while traversing directories, the whole directory is ignored.
 
