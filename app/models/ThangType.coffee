CocoModel = require './CocoModel'
SpriteBuilder = require 'lib/sprites/SpriteBuilder'
LevelComponent = require './LevelComponent'

utils = require 'lib/utils'

buildQueue = []

module.exports = class ThangType extends CocoModel
  @className: 'ThangType'
  @schema: require 'schemas/models/thang_type'
  @heroes:
    captain: '529ec584c423d4e83b000014'
    knight: '529ffbf1cf1818f2be000001'
    librarian: '52fbf74b7e01835453bd8d8e'
    equestrian: '52e95b4222efc8e70900175d'
    'potion-master': '52e9adf7427172ae56002172'
    thoktar: '52a00542cf1818f2be000006'
    'robot-walker': '5301696ad82649ec2c0c9b0d'
    'michael-heasell': '53e126a4e06b897606d38bef'
    'ian-elliott': '53e12be0d042f23505c3023b'
    'ninja': '52fc0ed77e01835453bd8f6c'
  @items:
    'simple-boots': '53e237bf53457600003e3f05'
  urlRoot: '/db/thang.type'
  building: {}

  initialize: ->
    super()
    @building = {}
    @spriteSheets = {}

    ## Testing memory clearing
    #f = =>
    #  console.info 'resetting raw data'
    #  @unset 'raw'
    #  @_previousAttributes.raw = null
    #setTimeout f, 40000

  resetRawData: ->
    @set('raw', {shapes: {}, containers: {}, animations: {}})

  resetSpriteSheetCache: ->
    @buildActions()
    @spriteSheets = {}
    @building = {}

  isFullyLoaded: ->
    # TODO: Come up with a better way to identify when the model doesn't have everything needed to build the sprite. ie when it's a projection without all the required data.
    return @get('actions') or @get('raster') # needs one of these two things

  loadRasterImage: ->
    return if @loadingRaster or @loadedRaster
    return unless raster = @get('raster')
    @rasterImage = $("<img src='/file/#{raster}' />")
    @loadingRaster = true
    @rasterImage.one('load', =>
      @loadingRaster = false
      @loadedRaster = true
      @trigger('raster-image-loaded', @))
    @rasterImage.one('error', =>
      @loadingRaster = false
      @trigger('raster-image-load-errored', @)
    )

  getActions: ->
    return {} unless @isFullyLoaded()
    return @actions or @buildActions()

  buildActions: ->
    return null unless @isFullyLoaded()
    @actions = $.extend(true, {}, @get('actions'))
    for name, action of @actions
      action.name = name
      for relatedName, relatedAction of action.relatedActions ? {}
        relatedAction.name = action.name + '_' + relatedName
        @actions[relatedAction.name] = relatedAction
    @actions

  fillOptions: (options) ->
    options ?= {}
    options = _.clone options
    options.resolutionFactor ?= SPRITE_RESOLUTION_FACTOR
    options.async ?= false
    options.thang = null  # Don't hold onto any bad Thang references.
    options

  buildSpriteSheet: (options) ->
    return false unless @isFullyLoaded() and @get 'raw'
    @options = @fillOptions options
    key = @spriteSheetKey(@options)
    if ss = @spriteSheets[key] then return ss
    if @building[key]
      @options = null
      return key
    @t0 = new Date().getTime()
    @initBuild(options)
    @addGeneralFrames() unless @options.portraitOnly
    @addPortrait()
    @building[key] = true
    result = @finishBuild()
    return result

  initBuild: (options) ->
    @buildActions() if not @actions
    @vectorParser = new SpriteBuilder(@, options)
    @builder = new createjs.SpriteSheetBuilder()
    @builder.padding = 2
    @frames = {}

  addPortrait: ->
    # The portrait is built very differently than the other animations, so it gets a separate function.
    return unless @actions
    portrait = @actions.portrait
    return unless portrait
    scale = portrait.scale or 1
    pt = portrait.positions?.registration
    rect = new createjs.Rectangle(pt?.x/scale or 0, pt?.y/scale or 0, 100/scale, 100/scale)
    if portrait.animation
      mc = @vectorParser.buildMovieClip portrait.animation
      mc.nominalBounds = mc.frameBounds = null # override what the movie clip says on bounding
      @builder.addMovieClip(mc, rect, scale)
      frames = @builder._animations[portrait.animation].frames
      frames = @mapFrames(portrait.frames, frames[0]) if portrait.frames?
      @builder.addAnimation 'portrait', frames, true
    else if portrait.container
      s = @vectorParser.buildContainerFromStore(portrait.container)
      frame = @builder.addFrame(s, rect, scale)
      @builder.addAnimation 'portrait', [frame], false

  addGeneralFrames: ->
    framesMap = {}
    for animation in @requiredRawAnimations()
      name = animation.animation
      mc = @vectorParser.buildMovieClip name
      continue unless mc
      @builder.addMovieClip mc, null, animation.scale * @options.resolutionFactor
      framesMap[animation.scale + '_' + name] = @builder._animations[name].frames

    for name, action of @actions when action.animation
      continue if name is 'portrait'
      scale = action.scale ? @get('scale') ? 1
      frames = framesMap[scale + '_' + action.animation]
      continue unless frames
      frames = @mapFrames(action.frames, frames[0]) if action.frames?
      next = true
      next = action.goesTo if action.goesTo
      next = false if action.loops is false
      @builder.addAnimation name, frames, next

    for name, action of @actions when action.container and not action.animation
      continue if name is 'portrait'
      scale = @options.resolutionFactor * (action.scale or @get('scale') or 1)
      s = @vectorParser.buildContainerFromStore(action.container)
      continue unless s
      frame = @builder.addFrame(s, s.bounds, scale)
      @builder.addAnimation name, [frame], false

  requiredRawAnimations: ->
    required = []
    for name, action of @get('actions')
      continue if name is 'portrait'
      allActions = [action].concat(_.values (action.relatedActions ? {}))
      for a in allActions when a.animation
        scale = if name is 'portrait' then a.scale or 1 else a.scale or @get('scale') or 1
        animation = {animation: a.animation, scale: scale}
        animation.portrait = name is 'portrait'
        unless _.find(required, (r) -> _.isEqual r, animation)
          required.push animation
    required

  mapFrames: (frames, frameOffset) ->
    return frames unless _.isString(frames) # don't accidentally do this again
    (parseInt(f, 10) + frameOffset for f in frames.split(','))

  finishBuild: ->
    return if _.isEmpty(@builder._animations)
    key = @spriteSheetKey(@options)
    spriteSheet = null
    if @options.async
      buildQueue.push @builder
      @builder.t0 = new Date().getTime()
      @builder.buildAsync() unless buildQueue.length > 1
      @builder.on 'complete', @onBuildSpriteSheetComplete, @, true, [@builder, key, @options]
      @builder = null
      return key
    spriteSheet = @builder.build()
    @logBuild @t0, false, @options.portraitOnly
    @spriteSheets[key] = spriteSheet
    @building[key] = false
    @builder = null
    @options = null
    spriteSheet

  onBuildSpriteSheetComplete: (e, data) ->
    [builder, key, options] = data
    @logBuild builder.t0, true, options.portraitOnly
    buildQueue = buildQueue.slice(1)
    buildQueue[0].t0 = new Date().getTime() if buildQueue[0]
    buildQueue[0]?.buildAsync()
    @spriteSheets[key] = e.target.spriteSheet
    @building[key] = false
    @trigger 'build-complete', {key: key, thangType: @}
    @vectorParser = null

  logBuild: (startTime, async, portrait) ->
    kind = if async then 'Async' else 'Sync '
    portrait = if portrait then '(Portrait)' else ''
    name = _.string.rpad @get('name'), 20
    time = _.string.lpad '' + new Date().getTime() - startTime, 6
    console.debug "Built sheet:  #{name} #{time}ms  #{kind}  #{portrait}"

  spriteSheetKey: (options) ->
    colorConfigs = []
    for groupName, config of options.colorConfig or {}
      colorConfigs.push "#{groupName}:#{config.hue}|#{config.saturation}|#{config.lightness}"
    colorConfigs = colorConfigs.join ','
    portraitOnly = !!options.portraitOnly
    "#{@get('name')} - #{options.resolutionFactor} - #{colorConfigs} - #{portraitOnly}"

  getPortraitImage: (spriteOptionsOrKey, size=100) ->
    src = @getPortraitSource(spriteOptionsOrKey, size)
    return null unless src
    $('<img />').attr('src', src)

  getPortraitSource: (spriteOptionsOrKey, size=100) ->
    return @getPortraitURL() if @get('rasterIcon') or @get('raster')
    stage = @getPortraitStage(spriteOptionsOrKey, size)
    stage?.toDataURL()

  getPortraitStage: (spriteOptionsOrKey, size=100) ->
    return unless @isFullyLoaded()
    key = spriteOptionsOrKey
    key = if _.isString(key) then key else @spriteSheetKey(@fillOptions(key))
    spriteSheet = @spriteSheets[key]
    if not spriteSheet
      options = if _.isPlainObject spriteOptionsOrKey then spriteOptionsOrKey else {}
      options.portraitOnly = true
      spriteSheet = @buildSpriteSheet(options)
    return if _.isString spriteSheet
    return unless spriteSheet
    canvas = $("<canvas width='#{size}' height='#{size}'></canvas>")
    console.log 'made canvas', canvas, 'with size', size unless canvas[0]
    stage = new createjs.Stage(canvas[0])
    sprite = new createjs.Sprite(spriteSheet)
    pt = @actions.portrait?.positions?.registration
    sprite.regX = pt?.x or 0
    sprite.regY = pt?.y or 0
    sprite.framerate = @actions.portrait?.framerate ? 20
    sprite.gotoAndStop 'portrait'
    stage.addChild(sprite)
    stage.update()
    stage.startTalking = ->
      sprite.gotoAndPlay 'portrait'
      return if @tick
      @tick = (e) => @update(e)
      createjs.Ticker.addEventListener 'tick', @tick
    stage.stopTalking = ->
      sprite.gotoAndStop 'portrait'
      @update()
      createjs.Ticker.removeEventListener 'tick', @tick
      @tick = null
    stage

  uploadGenericPortrait: (callback, src) ->
    src ?= @getPortraitSource()
    return callback?() unless src and src.startsWith 'data:'
    src = src.replace('data:image/png;base64,', '').replace(/\ /g, '+')
    body =
      filename: 'portrait.png'
      mimetype: 'image/png'
      path: "db/thang.type/#{@get('original')}"
      b64png: src
      force: 'true'
    $.ajax('/file', {type: 'POST', data: body, success: callback or @onFileUploaded})

  onFileUploaded: =>
    console.log 'Image uploaded'

  @loadUniversalWizard: ->
    return @wizardType if @wizardType
    wizOriginal = '52a00d55cf1818f2be00000b'
    url = "/db/thang.type/#{wizOriginal}/version"
    @wizardType = new module.exports()
    @wizardType.url = -> url
    @wizardType.fetch()
    @wizardType

  getPortraitURL: ->
    if iconURL = @get('rasterIcon')
      return "/file/#{iconURL}"
    if rasterURL = @get('raster')
      return "/file/#{rasterURL}"
    "/file/db/thang.type/#{@get('original')}/portrait.png"

  # Item functions

  getAllowedSlots: ->
    itemComponentRef = _.find(
      @get('components') or [],
      (compRef) -> compRef.original is LevelComponent.ItemID)
    return itemComponentRef?.config?.slots or ['right-hand']  # ['right-hand'] is default

  getAllowedHeroClasses: ->
    return [heroClass] if heroClass = @get 'heroClass'
    ['Warrior', 'Ranger', 'Wizard']

  getHeroStats: ->
    # Translate from raw hero properties into appropriate display values for the PlayHeroesModal.
    # Adapted from https://docs.google.com/a/codecombat.com/spreadsheets/d/1BGI1bzT4xHvWA81aeyIaCKWWw9zxn7-MwDdydmB5vw4/edit#gid=809922675
    return unless heroClass = @get('heroClass')
    components = @get('components') or []
    unless equipsConfig = _.find(components, original: LevelComponent.EquipsID)?.config
      return console.warn @get('name'), 'is not an equipping hero, but you are asking for its hero stats. (Did you project away components?)'
    unless movesConfig = _.find(components, original: LevelComponent.MovesID)?.config
      return console.warn @get('name'), 'is not a moving hero, but you are asking for its hero stats.'
    @classStatAverages ?=
      attack: {Warrior: 7.5, Ranger: 5, Wizard: 2.5}
      health: {Warrior: 7.5, Ranger: 5, Wizard: 3.5}
    stats = {skills: []}  # TODO: find skills
    rawNumbers = attack: equipsConfig.attackDamageFactor ? 1, health: equipsConfig.maxHealthFactor ? 1, speed: movesConfig.maxSpeed
    for prop in ['attack', 'health']
      stat = rawNumbers[prop]
      if stat < 1
        classSpecificScore = 10 - 5 / stat
      else
        classSpecificScore = stat * 5
      classAverage = @classStatAverages[prop][@get('heroClass')]
      stats[prop] = Math.round(2 * ((classAverage - 2.5) + classSpecificScore / 2)) / 2 / 10
    minSpeed = 4
    maxSpeed = 16
    speedRange = maxSpeed - minSpeed
    speedPoints = rawNumbers.speed - minSpeed
    stats.speed = Math.round(20 * speedPoints / speedRange) / 2 / 10
    stats

  getFrontFacingStats: ->
    components = @get('components') or []
    unless itemConfig = _.find(components, original: LevelComponent.ItemID)?.config
      console.warn @get('name'), 'is not an item, but you are asking for its stats.'
      return props: [], stats: {}
    props = itemConfig.programmableProperties ? []
    props = props.concat itemConfig.moreProgrammableProperties ? []
    stats = {}
    for stat, modifiers of itemConfig.stats ? {}
      stats[stat] = @formatStatDisplay stat, modifiers
    for stat in itemConfig.extraHUDProperties ? []
      stats[stat] ?= null  # Find it in the other Components.
    for component in components
      continue unless config = component.config
      for stat, value of stats when not value?
        value = config[stat]
        continue unless value?
        stats[stat] = @formatStatDisplay stat, setTo: value
        if stat is 'attackDamage'
          dps = (value / (config.cooldown or 0.5)).toFixed(1)
          stats[stat].display += " (#{dps} DPS)"
      if config.programmableSnippets
        props = props.concat config.programmableSnippets
    for stat, value of stats when not value?
      stats[stat] = name: stat, display: '???'
    props: props, stats: stats

  formatStatDisplay: (name, modifiers) ->
    i18nKey = {
      maxHealth: 'health'
      maxSpeed: 'speed'
      healthReplenishRate: 'regeneration'
      attackDamage: 'attack'
      attackRange: 'range'
      shieldDefenseFactor: 'blocks'
      visualRange: 'range'
      throwDamage: 'attack'
      throwRange: 'range'
    }[name]

    if i18nKey
      name = $.i18n.t 'choose_hero.' + i18nKey
    else
      name = _.string.humanize name

    format = ''
    format = 'm' if /(range|radius|distance|vision)$/i.test name
    format ||= 's' if /cooldown$/i.test name
    format ||= 'm/s' if /speed$/i.test name
    format ||= '/s' if /(regeneration| rate)$/i.test name
    value = modifiers.setTo
    if /(blocks)$/i.test name
      format ||= '%'
      value = (value*100).toFixed(1)
    value = value.join ', ' if _.isArray value
    display = []
    display.push "#{value}#{format}" if value?
    display.push "+#{modifiers.addend}#{format}" if modifiers.addend > 0
    display.push "#{modifiers.addend}#{format}" if modifiers.addend < 0
    display.push "x#{modifiers.factor}" if modifiers.factor? and modifiers.factor isnt 1
    display = display.join ', '
    display = display.replace /9001m?/, 'Infinity'
    name: name, display: display

  isSilhouettedItem: ->
    return console.error "Trying to determine whether #{@get('name')} should be a silhouetted item, but it has no gem cost." unless @get 'gems'
    console.info "Add (or make sure you have fetched) a tier for #{@get('name')} to more accurately determine whether it is silhouetted." unless @get('tier')?
    tier = @get 'tier'
    if tier?
      return @levelRequiredForItem() > me.level()
    points = me.get('points')
    expectedTotalGems = (points ? 0) * 1.5   # Not actually true, but roughly kinda close for tier 0, kinda tier 1
    @get('gems') > (100 + expectedTotalGems) * 1.2

  levelRequiredForItem: ->
    return console.error "Trying to determine what level is required for #{@get('name')}, but it has no tier." unless @get('tier')?
    tier = @get 'tier'
    me.constructor.levelForTier(Math.pow(tier, 0.7))
