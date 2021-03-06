{SelectListView, $$} = require 'atom-space-pen-views'
fs = require 'fs-plus'
_path = require 'path'
_ = require 'underscore-plus'
{match} = require 'fuzzaldrin'

settings = require './settings'

# Utils
# -------------------------
getPathDepth = (path) ->
  path.split(_path.sep).length

isGitRepository = (path) ->
  fs.isDirectorySync _path.join(path, '.git')

class View extends SelectListView
  # Copied from FuzzzyFinder's and modified a little.
  @highlightMatches: (context, path, matches, offsetIndex=0) ->
    lastIndex = 0
    matchedChars = [] # Build up a set of matched chars to be more semantic

    for matchIndex in matches
      matchIndex -= offsetIndex
      continue if matchIndex < 0 # If marking up the basename, omit path matches
      unmatched = path.substring(lastIndex, matchIndex)
      if unmatched
        context.span matchedChars.join(''), class: 'character-match' if matchedChars.length
        matchedChars = []
        context.text unmatched
      matchedChars.push(path[matchIndex])
      lastIndex = matchIndex + 1

    context.span matchedChars.join(''), class: 'character-match' if matchedChars.length
    # Remaining characters are plain text
    context.text path.substring(lastIndex)

  initialize: (defaultPath = true) ->
    super
    @addClass('enhanced-project-folder')
    atom.commands.add @element,
      'enhanced-project-folder:replace': => @replace()
      'enhanced-project-folder:switch-action': => @switchAction()
      'enhanced-project-folder:confirm-and-continue': => @confirmAndContinue()
      'enhanced-project-folder:go-into': => @goInto()
      'enhanced-project-folder:go-back': => @goBack()

    @panel ?= atom.workspace.addModalPanel({item: this, visible: false})
    if defaultPath
      @defaultDirectories = _.uniq @getNormalDirectories().concat(@getGitDirectories())
    else
      @defaultDirectories = @getRootDirectories()
    @paths = []
    this

  viewForItem: (item) ->
    matches  = match(item, @getFilterQuery())
    basename = _path.basename(item)
    $$ ->
      baseOffset = item.length - basename.length
      @li class: 'two-lines', =>
        @div {class: "primary-line file icon icon-repo", 'data-name': basename, 'data-path': item}, =>
          View.highlightMatches(this, basename, matches, baseOffset)
        @div {class: 'secondary-line path no-icon'}, =>
          View.highlightMatches(this, item, matches)

  getItems: (dir = '') ->
    loadedPaths = atom.project.getPaths()
    switch @action
      when 'remove'
        dirs = loadedPaths
      when 'add'
        if dir
          dirs = []
          for path in fs.listSync(fs.normalize(dir)) when fs.isDirectorySync(path)
            dirs.push path
        else
          dirs = @defaultDirectories

        dirs = _.reject(dirs, (path) -> _path.basename(path) in settings.get('ignoreDirectories'))
        if settings.get('hideLoadedFolderFromAddList')
          dirs = _.reject(dirs, (path) -> path in loadedPaths)

    dirs.map (dir) ->
      dir.replace fs.getHomeDirectory(), '~'

  getNormalDirectories: ->
    dirs = []
    for dir in settings.get('projectDefaultDirectories')
      for path in fs.listSync(fs.normalize(dir)) when fs.isDirectorySync(path)
        dirs.push path
    dirs

  getGitDirectories: ->
    maxDepth = settings.get('gitProjectSearchMaxDepth')

    dirs = []
    for dir in settings.get('gitProjectDirectories')
      dir = fs.normalize(dir)
      continue unless fs.isDirectorySync(dir)

      baseDepth = getPathDepth(dir)
      fs.traverseTreeSync dir, (->), (path) ->
        if (getPathDepth(path) - baseDepth) > maxDepth
          false
        else
          dirs.push path if isGitRepository(path)
          true
    dirs

  getRootDirectories: ->
    dirs = []
    for dir in settings.get('searchRootDirectories')
      for path in fs.listSync(fs.normalize(dir)) when fs.isDirectorySync(path)
        dirs.push path
    dirs

  populateList: ->
    super
    @removeClass 'add remove'
    @addClass @action

  # @action should be 'add' or 'remove'
  start: (@action) ->
    @storeFocusedElement()
    @setItems @getItems()
    @panel.show()
    @focusFilterEditor()

  confirmAndContinue: ->
    selectedItem = @getSelectedItem()
    this[@action](fs.normalize(selectedItem))

    selectedItemView = @getSelectedItemView()
    @selectNextItemView()
    selectedItemView.remove()
    @items = (item for item in @items when item isnt selectedItem)

  confirmed: (item) ->
    this[@action] fs.normalize(item)
    @cancel()

  cancelled: ->
    @action = null
    @panel.hide()
    if atom.workspace.getPaneItems().length
      atom.workspace.getActivePane().activate()
    else
      # For smooth navigation.
      workspaceElement = atom.views.getView(atom.workspace)
      atom.commands.dispatch(workspaceElement, 'tree-view:toggle-focus')

  switchAction: ->
    @action = if @action is 'add' then 'remove' else 'add'
    @setItems @getItems()

  add: (path) ->
    atom.project.addPath path

  remove: (path) ->
    if settings.get('closeItemsForRemovedProject')
      dir = _.detect(atom.project.getDirectories(), (d) -> d.getPath() is path)
      for e in atom.workspace.getTextEditors() when dir.contains(e.getPath())
        e.destroy()

    atom.project.removePath path

  replace: ->
    selected = @getSelectedItem()
    projectPath = fs.normalize(selected)
    @add projectPath
    for p in atom.project.getPaths() when p isnt projectPath
      @remove p

    @cancel()

  goInto: ->
    selected = @getSelectedItem()
    projectPath = fs.normalize(selected)
    results = @getItems(projectPath)
    if results && results.length != 0
      @paths.unshift(projectPath)
      @setItems results

  goBack: ->
    @paths.shift()
    @setItems @getItems(@paths[0])

module.exports = View
