{ EventEmitter2 } = require 'eventemitter2'
{ locationDataToRange } = require './location_data_util'

module.exports =
class Watcher extends EventEmitter2

  constructor: (@moduleManager, @editorView) ->
    super()
    @editor = @editorView.editor
    @editor.on 'grammar-changed', @verifyGrammar
    @moduleManager.on 'changed', @verifyGrammar
    @verifyGrammar()

  destruct: =>
    @removeAllListeners()
    @deactivate()
    @editor.off 'grammar-changed', @verifyGrammar
    @moduleManager.off 'changed', @verifyGrammar

    delete @moduleManager
    delete @editorView
    delete @editor
    delete @module

  onDestroyed: =>
    @emit 'destroyed', @


  ###
  Grammar valification process
  1. Detect grammar changed.
  2. Destroy instances and listeners.
  3. Exit process when the language plugin of the grammar can't be found.
  4. Create instances and listeners.
  ###

  verifyGrammar: =>
    scopeName = @editor.getGrammar().scopeName
    module = @moduleManager.getModule scopeName
    return if module is @module
    @deactivate()
    return unless module?
    @module = module
    @activate()

  activate: ->
    # Setup model
    @ripper = new @module.Ripper()

    # Start listening
    @editorView.on 'cursor:moved', @onCursorMoved
    @editor.on 'destroyed', @onDestroyed
    @editor.buffer.on 'changed', @onBufferChanged

    # Execute
    @parse()

  deactivate: ->
    # Stop listening
    @editorView.off 'cursor:moved', @onCursorMoved
    @editor.off 'destroyed', @onDestroyed
    @editor.buffer.off 'changed', @onBufferChanged
    clearTimeout @bufferChangedTimeoutId
    clearTimeout @cursorMovedTimeoutId

    # Destruct instances
    @ripper?.destruct()

    # Remove references
    delete @bufferChangedTimeoutId
    delete @cursorMovedTimeoutId
    delete @module
    delete @ripper
    delete @renamingCursor
    delete @renamingMarkers


  ###
  Reference finder process
  1. Stop listening cursor move event and reset views.
  2. Parse.
  3. Show errors and exit process when compile error is thrown.
  4. Show references.
  5. Start listening cursor move event.
  ###

  parse: =>
    @editorView.off 'cursor:moved', @onCursorMoved
    @destroyReferences()
    @destroyErrors()
    text = @editor.buffer.getText()
    if text isnt @cachedText
      @cachedText = text
      @ripper.parse text, @onRipperParsed
    else
      @onRipperParsed()

  onRipperParsed: (returns) =>
    if returns?.errors?
      @createErrors returns.errors
    else
      @createReferences()
      @editorView.off 'cursor:moved', @onCursorMoved
      @editorView.on 'cursor:moved', @onCursorMoved

  destroyErrors: ->
    return unless @errorMarkers?
    for marker in @errorMarkers
      marker.destroy()
    delete @errorMarkers

  createErrors: (errors) =>
    @errorMarkers = for { location, range, message } in errors
      if location? #TODO deprecate verification of the location in v0.5
        range = locationDataToRange location

      marker = @editor.markBufferRange range
      @editor.decorateMarker marker, type: 'highlight', class: 'refactor-error'
      @editor.decorateMarker marker, type: 'gutter', class: 'refactor-error'
      marker

  destroyReferences: ->
    return unless @referenceMarkers?
    for marker in @referenceMarkers
      marker.destroy()
    delete @referenceMarkers

  createReferences: ->
    @ripper.find @editor.getSelectedBufferRange().start, @onRipperFound

  onRipperFound: (ranges) =>
    @destroyReferences()
    @referenceMarkers = for range in ranges
      marker = @editor.markBufferRange range
      @editor.decorateMarker marker, type: 'highlight', class: 'refactor-reference'
      marker


  ###
  Renaming life cycle.
  1. When detected rename command, start renaming process.
  2. When the cursors move out from the symbols, abort and exit renaming process.
  3. When detected done command, exit renaming process.
  ###

  rename: ->
    # When this editor is not active, returns false to abort keyboard binding.
    return false unless @isActive()

    # Find references.
    # When no reference exists, do nothing.
    cursor = @editor.getCursor()
    @ripper.find cursor.getBufferPosition(), @onRipperRenameReady

  onRipperRenameReady: (ranges) =>
    return false if ranges.length is 0

    # Pause highlighting life cycle.
    @destroyReferences()
    @editor.buffer.off 'changed', @onBufferChanged
    @editorView.off 'cursor:moved', @onCursorMoved

    #TODO Cursor::clearAutoScroll()

    # Register the triggered cursor.
    @renamingCursor = @editor.getCursor()
    # Select references.
    # Register the markers of the references' ranges.
    # Highlight these markers.
    @renamingMarkers = for range in ranges
      @editor.addSelectionForBufferRange range
      marker = @editor.markBufferRange range
      @editor.decorateMarker marker, type: 'highlight', class: 'refactor-reference'
      marker
    # Start renaming life cycle.
    @editorView.off 'cursor:moved', @abort
    @editorView.on 'cursor:moved', @abort

    # Returns true not to abort keyboard binding.
    true

  abort: =>
    # When this editor is not active, do nothing.
    return unless @isActive() and @renamingCursor? and @renamingMarkers?

    # Verify all cursors are in renaming markers.
    # When the cursor is out of marker at least one, abort renaming.
    selectedRanges = @editor.getSelectedBufferRanges()
    isMarkersContainsCursors = true
    for marker in @renamingMarkers
      markerRange = marker.getBufferRange()
      isMarkerContainsCursor = false
      for selectedRange in selectedRanges
        isMarkerContainsCursor or= markerRange.containsRange selectedRange
        break if isMarkerContainsCursor
      isMarkersContainsCursors and= isMarkerContainsCursor
      break unless isMarkersContainsCursors
    return if isMarkersContainsCursors
    @done()

  done: ->
    # When this editor is not active, returns false to abort keyboard binding.
    return false unless @isActive() and @renamingCursor? and @renamingMarkers?

    # Stop renaming life cycle.
    @editorView.off 'cursor:moved', @abort

    # Reset cursor's position to the triggerd cursor's position.
    @editor.setCursorBufferPosition @renamingCursor.getBufferPosition()
    delete @renamingCursor
    # Remove all markers for renaming.
    for marker in @renamingMarkers
      marker.destroy()
    delete @renamingMarkers

    # Start highlighting life cycle.
    @parse()
    @editor.buffer.off 'changed', @onBufferChanged
    @editor.buffer.on 'changed', @onBufferChanged
    @editorView.off 'cursor:moved', @onCursorMoved
    @editorView.on 'cursor:moved', @onCursorMoved

    # Returns true not to abort keyboard binding.
    true


  ###
  User events
  ###

  onBufferChanged: =>
    clearTimeout @bufferChangedTimeoutId
    @bufferChangedTimeoutId = setTimeout @parse, 0

  onCursorMoved: =>
    clearTimeout @cursorMovedTimeoutId
    @cursorMovedTimeoutId = setTimeout @onCursorMovedAfter, 0

  onCursorMovedAfter: =>
    @createReferences()


  ###
  Utility
  ###

  isActive: ->
    @module? and atom.workspaceView.getActivePaneItem() is @editor

  # Range to pixel based start and end range for each row.
  rangeToRows: ({ start, end }) ->
    for raw in [start.row..end.row] by 1
      rowRange = @editor.buffer.rangeForRow raw
      point =
        left : if raw is start.row then start else rowRange.start
        right: if raw is end.row then end else rowRange.end
      pixel =
        tl: @editorView.pixelPositionForBufferPosition point.left
        br: @editorView.pixelPositionForBufferPosition point.right
      pixel.br.top += @editorView.lineHeight
      pixel
