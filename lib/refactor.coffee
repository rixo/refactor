{ Disposable, CompositeDisposable } = require 'atom'
Watcher = require './watcher'
ModuleManager = require './module_manager'
{ packages: packageManager } = atom
d = (require './debug') 'refactor'

module.exports =
new class Main

  config:
    highlightError:
      type: 'boolean'
      default: true
    highlightReference:
      type: 'boolean'
      default: true


  activate: (state) ->
    console.time('activate refactor')
    d 'activate'

    console.time('init module manager')
    @moduleManager = new ModuleManager
    console.timeEnd('init module manager')
    @watchers = new Set
    disposeWatchers = () -> w.dispose() for w of @watchers

    @disposables = new CompositeDisposable
    @disposables.add @moduleManager
    @disposables.add new Disposable disposeWatchers
    @disposables.add atom.workspace.observeTextEditors (editor) =>
      watcher = new Watcher @moduleManager, editor
      @watchers.add watcher
      editor.onDidDestroy =>
        @watchers.delete watcher
        watcher.dispose()
    @disposables.add atom.commands.add 'atom-text-editor', 'refactor:rename', @onRename
    @disposables.add atom.commands.add 'atom-text-editor', 'refactor:done', @onDone

    @disposables.add atom.commands.add 'atom-text-editor', 'refactor-navigate:previous', @onJumpPrevious
    @disposables.add atom.commands.add 'atom-text-editor', 'refactor-navigate:next', @onJumpNext

    console.timeEnd('activate refactor')

  deactivate: ->
    d 'deactivate'
    @disposables.dispose()
    @moduleManager = null
    @watchers = null

  serialize: ->

  onJumpPrevious: (e) =>
    isExecuted = false
    @watchers.forEach (watcher) ->
      isExecuted or= watcher.jump(-1)
    return if isExecuted
    e.abortKeyBinding()

  onJumpNext: (e) =>
    isExecuted = false
    @watchers.forEach (watcher) ->
      isExecuted or= watcher.jump(1)
    return if isExecuted
    e.abortKeyBinding()

  onRename: (e) =>
    isExecuted = false
    @watchers.forEach (watcher) ->
      isExecuted or= watcher.rename()
    d 'rename', isExecuted
    return if isExecuted
    e.abortKeyBinding()

  onDone: (e) =>
    isExecuted = false
    @watchers.forEach (watcher) ->
      isExecuted or= watcher.done()
    return if isExecuted
    e.abortKeyBinding()
