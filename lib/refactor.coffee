Watcher = require './watcher'
ModuleManager = require './module_manager'
{ CompositeDisposable } = require 'atom'
{ packages: packageManager } = atom
d = (require 'debug/browser') 'refactor'

module.exports =
new class Main

  config:
    highlightError:
      type: 'boolean'
      default: true
    highlightReference:
      type: 'boolean'
      default: true


  ###
  Life cycle
  ###

  activate: (state) ->
    d 'activate'
    @moduleManager = new ModuleManager
    @disposables = new CompositeDisposable
    @watchers = []

    @disposables.add atom.workspace.observeTextEditors @onCreated
    @disposables.add atom.commands.add 'atom-text-editor', 'refactor:rename', @onRename
    @disposables.add atom.commands.add 'atom-text-editor', 'refactor:done', @onDone

  deactivate: ->
    @moduleManager.destruct()
    delete @moduleManager
    for watcher in @watchers
      watcher.destruct()
    delete @watchers

    @disposables.dispose()
    @disposables = null

  serialize: ->


  ###
  Events
  ###

  onCreated: (editor) =>
    watcher = new Watcher @moduleManager, editor
    watcher.on 'destroyed', @onDestroyed
    @watchers.push watcher

  onDestroyed: (watcher) =>
    watcher.destruct()
    @watchers.splice @watchers.indexOf(watcher), 1

  onRename: (e) =>
    isExecuted = false
    for watcher in @watchers
      isExecuted or= watcher.rename()
    d 'rename', isExecuted
    return if isExecuted
    e.abortKeyBinding()

  onDone: (e) =>
    isExecuted = false
    for watcher in @watchers
      isExecuted or= watcher.done()
    return if isExecuted
    e.abortKeyBinding()
