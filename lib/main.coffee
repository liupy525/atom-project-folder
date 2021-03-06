{CompositeDisposable} = require 'atom'
settings = require './settings'
DirectoriesView = require './view'

module.exports =
  config: settings.config

  activate: ->
    @DirectoriesView = new DirectoriesView
    @subscriptions = new CompositeDisposable
    @subscriptions.add atom.commands.add 'atom-workspace',
      'enhanced-project-folder:add': => (new DirectoriesView).start('add')
      'enhanced-project-folder:remove': => (new DirectoriesView).start('remove')
      'enhanced-project-folder:search': => (new DirectoriesView false).start('add')

  deactivate: ->
    @subscriptions.dispose()
    @DirectoriesView?.destroy?()
    {@subscriptions, @DirectoriesView} = {}
