$(document).ready ->
  if $('.map-controller').length
    wrapper = new MapWrapper('map')
    map = wrapper.map
    $('#toggle').on 'click', ->
      setTimeout ->
        map.invalidateSize()
      , 500

  # map variable for debugging purposes
  window.map     = map
  window.wrapper = wrapper

MapWrapper = L.Class.extend
  _layers:       {}
  _drawedItems:  {}
  _requestsPool: []
  _openPopups:   []

  initialize: (domId)->
    this.map = L.map 'map',
      center: new L.LatLng(38, -93)
      zoom: 4
      layers: this.getBaseLayer()
    t = this
    this.map.on
      dragend: ->
        t.onDragend()
      zoomstart: ->
        t.onZoomstart()
      zoomend: ->
        t.onZoomend()
    this.updateMapMarkers()

  onDragend: ->
    this.updateMapMarkers()

  onZoomstart: ->
    this.closeAllOpenPopups()

  onZoomend: ->
    this.updateMapMarkers()

  updateMapMarkers: ->
    stateLayer  = this.getStateLayer()
    pointsLayer = this.getRegularLayer()
    switch
      when this.map.getZoom() in [4..6]
        this.map.removeLayer pointsLayer
        this.map.addLayer    stateLayer
      else
        this.requestRegularMarkers(this.getMapPosition())
        this.map.removeLayer stateLayer
        this.map.addLayer    pointsLayer

  getMapPosition: ->
    center    = this.map.getCenter()
    northEast = this.map.getBounds().getNorthEast()
    lat: center.lat
    lng: center.lng
    radius: center.distanceTo(northEast) / 1000

  turnProgressCursor: (turn)->
    cursor = if turn then 'progress' else ''
    $(this.map.getContainer()).css(cursor: cursor)

  closeAllOpenPopups: ->
    $.each this._openPopups, (i,popup)->
      popup._close()

  getBaseLayer: ->
    unless this._layers.base
      tileUrl = 'http://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png'
      copyright = 'Map data &copy; <a href="http://openstreetmap.org">OpenStreetMap</a> contributors, <a href="http://creativecommons.org/licenses/by-sa/2.0/">CC-BY-SA</a>'
      this._layers.base = L.tileLayer tileUrl, attribution: copyright, minZoom: 4, maxZoom: 18
    this._layers.base

  getStateLayer: ->
    unless this._layers.state
      statesMarkers = []
      if window.states instanceof Array
        t = this
        $.each window.states, (i,state)->
          marker = new L.marker [state.lat, state.lng],
            icon: new L.DivIcon
              html: '<div class="mapCluster"><span class="resultnumber">' + state.count + '</span></div>'
              className: 'dot more-results'
              iconSize: new L.Point 20, 20
          marker.data = state
          marker.on 'click', (e)->
            state = e.target.data
            t.openStatePopup state, e.target.getLatLng()
          statesMarkers.push marker
      markerCluster = new L.MarkerClusterGroup
        iconCreateFunction: (cluster) ->
          totalCount = 0
          $.each cluster.getAllChildMarkers(), (i,point)->
            totalCount += point.data.count if point.data.count
          new L.DivIcon({html: '<div class="mapCluster"><span class="resultnumber">' + totalCount + '</span></div>', className: 'dot more-results', iconSize: new L.Point(20, 20)})
        spiderfyOnMaxZoom: false
        showCoverageOnHover: false
        zoomToBoundsOnClick: false
      markerCluster.addLayers statesMarkers
      markerCluster.on 'clusterclick', (cluster)->
        relevantChilds = cluster.layer.getAllChildMarkers().sort (a,b)->
          b.data.count - a.data.count
        t.openStatePopup relevantChilds.shift().data, cluster.layer.getLatLng()


      this._layers.state = markerCluster
    this._layers.state

  openStatePopup: (state, latlng)->
    while this._requestsPool.length > 0
      this._requestsPool.shift().abort()

    t = this
    this._requestsPool.push $.ajax
      url: window.api_path
      data:
        'aggregatedCHO.spatial.state': state.name
        'page_size': 5
      dataType: 'jsonp'
      cache: true
      beforeSend: ->
        t.turnProgressCursor true
      success: (data)->
        if $.isPlainObject(data) and $.isArray(data.docs)
          points = $.map data.docs, (doc)->
            t.doc2point doc
          popup = t.generatePopup(points, state.name).setLatLng(latlng)
          t._openPopups.push popup.openOn t.map
      complete: ->
        t.turnProgressCursor false

  getRegularLayer: ->
    t = this
    unless this._layers.points
      markerCluster = new L.MarkerClusterGroup
        iconCreateFunction: (cluster) ->
          totalCount = cluster.getChildCount()
          new L.DivIcon({html: '<div class="mapCluster"><span class="resultnumber">' + totalCount + '</span></div>', className: 'dot more-results', iconSize: new L.Point(20, 20)})
        spiderfyOnMaxZoom: false
        showCoverageOnHover: false
        zoomToBoundsOnClick: false
      markerCluster.on 'clusterclick', (cluster)->
        points = cluster.layer.getAllChildMarkers()
        popupTitle = t.getClusterLocation(points)
        popup = t.generatePopup(points.slice(0,5), popupTitle).setLatLng(cluster.layer.getLatLng())
        t._openPopups.push popup.openOn(t.map)
      this._layers.points = markerCluster
    this._layers.points

  requestRegularMarkers: (position)->
    while this._requestsPool.length > 0
      this._requestsPool.shift().abort()

    t = this
    this._requestsPool.push $.ajax
      url: window.api_path
      data:
        'aggregatedCHO.spatial.coordinates': "#{position.lat},#{position.lng}"
        'aggregatedCHO.spatial.distance': "#{position.radius}km"
        'page_size': 500
      dataType: 'jsonp'
      cache: true
      beforeSend: ->
        t.turnProgressCursor true
      success: (data)->
        if $.isPlainObject(data) and $.isArray(data.docs)
          t.drawRegularItems data.docs
      complete: ->
        t.turnProgressCursor false

  drawRegularItems: (docs)->
    t = this
    toDraw = []
    $.each docs, (i, doc)->
      unless t._drawedItems[doc.id]
        t._drawedItems[doc.id] = true
        point = t.doc2point doc
        if point
          myIcon = L.divIcon
            className: 'dot'
            iconSize: new L.Point 0, 0
          marker = new L.marker([point.lat, point.lng], {icon: myIcon})
          marker.data = point
          marker.on 'click', (e)->
            popup = t.generatePopup(e.target).setLatLng(e.target.getLatLng())
            t._openPopups.push popup.openOn(t.map)
            popup.adjust 0, 10
          toDraw.push marker

    t.getRegularLayer().addLayers toDraw

  getClusterLocation: (points)->
    locations = {}
    $.each points, (i, point)->
      $.each point.data.location, (i,loc)->
        if locations[loc]
          locations[loc]++
        else
          locations[loc] = 1
    locationName = ''
    locationScore = 0
    $.each locations, (name, score)->
      if locationScore < score
        locationName = name
        locationScore = score
    locationName

  doc2point: (doc)->
    coordinates = try
      doc['aggregatedCHO.spatial.coordinates'][0].split ','
    catch error
      []
    location = doc['aggregatedCHO.spatial.name']
    location = [location] unless location instanceof Array
    point =
      id: doc.id
      title: doc['aggregatedCHO.title']
      thumbnail: doc['object.@id']
      type: doc['aggregatedCHO.type'] || ''
      creator: doc['aggregatedCHO.creator'] || ''
      location: location
      url: doc['isShownAt.@id']
      lat: coordinates.shift()
      lng: coordinates.shift()


  generatePopup: (points, title) ->
    points = [points] unless points instanceof Array

    html = ''
    $.each points, (i,point) ->
      point = if $.isPlainObject(point) then point else point.data
      content =
        """
          <h6> #{ point.type }</h6>
          <h4><a href="/item/#{ point.id }">#{ point.title }</a></h4>
          <p><span> #{ point.creator }</span></p>
          <a class="ViewObject" href="#{ point.url }" target="_blank">View Object <span class="icon-view-object" aria-hidden="true"></span></a>
        """
      if point.thumbnail
        html +=
          """
            <div class="box-row">
              <div class="box-right"><img src="#{ point.thumbnail }" /></div>
              <div class="box-left">#{ content }</div>
            </div>
          """
      else
        html += "<div class=\"box-row\">#{ content }</div>"

    html = '<div class="box-rows">' + html + '</div>' if points.length > 1
    html = "<h5>#{ title }</h5>" + html if title
    popup = new DPLAPopup offset: new L.Point(-10,-30)
    popup.setContent html


DPLAPopup = L.Popup.extend
  adjust: (x,y)->
    pos = L.DomUtil.getPosition this._container
    L.DomUtil.setPosition this._container, pos.add(new L.Point x,y)
  _initLayout: ->
    this._container = mapBox = L.DomUtil.create 'div', 'mapBox'
    L.DomEvent.disableClickPropagation mapBox
    closeButton = L.DomUtil.create 'a', 'closePopUp', mapBox
    closeButton.href = '#close'
    closeButton.innerHTML = '&#215;'
    L.DomEvent.on closeButton, 'click', this._onCloseButtonClick, this
    this._contentNode = L.DomUtil.create 'div', 'boxInner', mapBox
    L.DomEvent.on(this._contentNode, 'mousewheel', L.DomEvent.stopPropagation)
    this._tip = L.DomUtil.create('div', 'mapArrow', mapBox)
  _updateLayout: ->
    container = this._contentNode
    this._containerWidth = container.offsetWidth
    container.style.height =  container.offsetHeight + 'px'
    this._container.style.bottom = 50 + 'px'
    this._container.style.left = 50 + 'px'
  _updatePosition: ->
    pos = this._map.latLngToLayerPoint(this._latlng)
    animated = this._animated
    offset = this.options.offset
    if (animated)
      L.DomUtil.setPosition(this._container, pos)
    this._containerBottom = -offset.y - (animated ? 0 : pos.y)
    this._containerLeft = -Math.round(this._containerWidth / 2) + offset.x + (animated ? 0 : pos.x)
    adjust =
      x: 20
      y: 10
    this._container.style.bottom = (this._containerBottom + adjust.y) + 'px'
    this._container.style.left = (this._containerLeft + adjust.x) + 'px'