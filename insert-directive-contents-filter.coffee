'use strict'

RSVP      = require('rsvp')
path      = require('path')
fs        = require('fs')
async     = require('async')
Filter    = require('broccoli-filter')

symlinkOrCopySync = require('symlink-or-copy').sync

SprocketsResolver  = require('./resolver')
{ resolvePath } = require('bender-broccoli-utils')

# Mimic Sprocket-style `//= require ...` directives to concatenate JS/CSS via broccoli.
#
# You can pass in an existing `DependenciesCache` instance if you already have
# done a pass at calculating dependencies. For example:
#
#     sharedDependencyCache = new DependenciesCache
#
#     tree = CopyDependenciesFilter tree,
#       cache: sharedDependencyCache
#       loadPaths: externalLoadPaths
#
#     tree = compileSass tree,
#       sassDir: '.'
#       cssDir: '.'
#       importPath: externalLoadPaths
#
#     tree = compileCoffeescript tree
#
#     tree = InsertDirectiveContentsFilter tree,
#       cache: sharedDependencyCache
#       loadPaths: externalLoadPaths

class InsertDirectiveContentsFilter extends Filter
  # Save broccoli-filter cache to disk
  cacheByContent: true

  extensions: SprocketsResolver.REQUIREABLE_EXTENSIONS

  constructor: (inputTree, options = {}) ->
    if not (this instanceof InsertDirectiveContentsFilter)
      return new InsertDirectiveContentsFilter(inputTree, options)

    @inputTree = inputTree
    @options = options

    throw new Error "No dependencyCache passed in via InsertDirectiveContentsFilter's options (it is required, for now?)" unless @options.dependencyCache?

  # Take all the dependencies laid down in the `DependenciesCache` and insert
  # the content of each into the top of the file. Eg. the concatenation step, but done
  # after any other precompilers.
  processFile: (srcDir, destDir, relativePath) ->
    fileContents = origFileContents = fs.readFileSync(srcDir + '/' + relativePath, { encoding: 'utf8' })

    # Assumes that a pre-filled dependency cache instance was passed into this filter
    depTree = @options.dependencyCache.dependencyTreeForFile relativePath
    allRelativeDependencyPaths = depTree?.listOfAllDependenciesForType('sprockets') ? []
    allRelativeDependencyPaths.pop()  # remove the self dependency

    if not depTree? or allRelativeDependencyPaths.length is 0
      symlinkOrCopySync srcDir + '/' + relativePath, destDir + '/' + relativePath
    else
      # Remove the directive header if it still exists (might be a bit better if
      # only the directive lines in the header were removed)
      header = SprocketsResolver.extractHeader(fileContents)
      fileContents = fileContents.slice(header.length) if fileContents.indexOf(header) is 0

      # Hacky, `options.loadPaths` might be a function (revisit)
      dirsToCheck = [srcDir].concat(@options.loadPaths?() ? @options.loadPaths ? [])

      deferred = RSVP.defer()

      async.map allRelativeDependencyPaths, (filepath, callback) =>

        resolvedPath = resolvePath filepath,
          filename: srcDir + '/' + relativePath
          loadPaths: dirsToCheck

        fs.readFile resolvedPath, { encoding: 'utf8' }, callback
      , (err, contentsOfAllDependencies) ->
        if err
          deferred.reject err
        else
          newContents = contentsOfAllDependencies.join('\n') + fileContents

          if newContents isnt origFileContents
            console.log "Concatenating directive deps into #{relativePath}"
            fs.writeFile destDir + '/' + relativePath, newContents, { encoding: 'utf8' }, (err) ->
              if err
                deferred.reject err
              else
                deferred.resolve()
          else
            helpers.copyPreserveSync srcDir + '/' + relativePath, destDir + '/' + relativePath
            deferred.resolve()

      deferred.promise



module.exports = InsertDirectiveContentsFilter
