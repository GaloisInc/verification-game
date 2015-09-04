// Main entry point.
// task_name:  { function: string, group: string, name: string }
function startTask(task_name, realNames, here) {
  $('html,body').css('cursor', 'progress');
  galoisPost('/play/startTask'
        , task_name
        , function (task) {

      handleNewTask(task, realNames, here);
   });
}

var miniMapPic =
  { call:         { url: 'VA/MiniMap/call', width: 361, height: 225 }
  , concrete:     { url: 'VA/MiniMap/concrete', width: 422, height: 404 }
  , loop:         { url: 'VA/MiniMap/loop', width: 511, height: 460 }
  , precondition: { url: 'VA/MiniMap/precondition', width: 370, height: 336 }
  };


var grassTiles =
  { nw: '000', n: '001', ne: '002'
  , w : '018', c: '019', e : '020'
  , sw: '036', s: '037', se: '038'
  };

var lightGrayStone =
  { nw: '069', n: '070', ne: '071'
  , w : '051', c: '052', e : '053'
  , sw: '048', s: '047', se: '050'
  };

var grayStone =
  { nw: '078', n: '079', ne: '080'
  , w : '060', c: '061', e : '062'
  , sw: '057', s: '056', se: '059'
  };

var grassIsland =
  { nw: '013', n: '045', ne: '014'
  , w : '030', c: '019', e : '028'
  , sw: '031', s: '011', se: '032'
  };

var grayStoneRoof =
  { nw: '150', n: '151', ne: '152'
  , w : '060', c: '061', e : '062'
  , sw: '057', s: '056', se: '059'
  };

var lightGrayStoneRoof =
  { nw: '141', n: '142', ne: '143'
  , w : '051', c: '052', e : '053'
  , sw: '048', s: '047', se: '050'
  };




var theme =
  { asmpStyle: grayStone
  , inputStyle: lightGrayStone
  , inputIsle: grassIsland
  , bgStyle: '029'
  };





function handleNewTask(task, realNames, here) {
  var t = galoisRenderTask(here, realNames, task);
  $('html,body').css('cursor', 'auto');
  here.css('visibility', 'hidden');
  here.css('background-repeat', 'repeat');
//  here.css('background-image', 'url("' + kennyRPG(theme.bgStyle) + '")');

  var realName = realNames[task.name.function];
  if (realName === undefined) {
    realName = '?'
  }

  var label = $('<div/>')
              .css('text-align', 'center')
              .css('font-weight', 'bold')
              .css('font-family', 'monospace')
              .css('color', 'orange')
              .css('background-color', 'black')
              .text(task.name.function + ' / ' +
                    realName + ' / ' +
                    task.name.group + ' / ' +
                    task.name.name);


  galoisPost('/listTags', task.name, function(tags) {
    jQuery.each(tags,function(ix,tag) {
      label.append($('<span/>').text(' / ' + tag))
    })
  })

  here.empty()
     .append(label)
     .append(t.dom);
  t.drawGraph();
  here.css('visibility', 'visible');
  addCopyrights(here);
}


function loadSnapshot(snapshot, realNames, here) {
  $('html,body').css('cursor', 'progress');
  galoisPost('/play/loadSnapshot'
        , { snapshot: snapshot }
        , function (task) {
   getRealNames(function(realNames) {
     setTimeout(function () {
          handleNewTask(task, realNames, here);
     },0);
   });
  });
}


// Let the server know that we are done.
function finish_level(onDone) {
  galoisPost('/play/finishTask', {},
           function (data) {
               if (data.finished) {
                   onDone();
               } else {
                  if (data.tag === 'illegal') {
                    switch(data.explain.reason) {
                      case 'asserted_false':
                        alert ('You tried to assert false.');
                        break;
                      case 'contains_casts':
                        alert (data.explain.casts +
                                    ' cast(s) still need to be eliminated.');
                        break;
                    }
                  } else alert("Cannot finish: " + data.tag)
               }
           });
}





function galoisRenderTask(here, realNames, task) {
  var isCutTask = task.name.name === "CUT";
  var inputMap  = {};

  function onDone(how) {
    return function(ev) {
            if (isCutTask) {
              galoisPost
                ( '/play/finishCut'
                , { keep: how }
                , function (res) {
                     if (res.error) { alert(res.error_message); return; }
                     handleNewTask(res,realNames,here);
                  }
                );


            } else {
              // Ordinary tasks
              if (how === 'keep') {
                 finish_level(function () {
                    renderTaskGroup3(task.name.function, task.name.group, here);
                 });
              } else {
                    renderTaskGroup3(task.name.function, task.name.group, here);
              }
            }
           };
  }

  jQuery.each(task.inputs, function(unusedIx, input) {
    inputMap[input.id] = renderNormalInput(input);
  });

  jQuery.each(task.calls, function(unusedIx, input) {
    inputMap[input.id] = renderCallInput(input);
  });

  // Concrete assumptions
  var concreteAsmpsBgStruct = grassArea( null
                                       , 0.75 * $(window).height()
                                       , theme.asmpStyle
                                       );
  var concreteAsmpsBg       = concreteAsmpsBgStruct.dom;
  var concreteAsmps         = concreteAsmpsBgStruct.mid;

  // Freebies
  var freebies = $('<div/>')
                 .addClass('freebies')
                 .css('background-color', 'rgba(0,0,0,0.1)')

  concreteAsmps.append(freebies)

  var startCut =
               $('<img/>')
               .attr('src', '/static/img/kenny_rpg/PNG/rpgTile228.png')
               .addClass('clickable')
               .css('float', 'left')
               .css('z-index', '20')
               .click(function() {
                    galoisPost
                      ( '/play/startCut'
                      , { goalid: curGInfo.goalId }
                      , function (res) {
                          if (res.error) { alert(res.error_message); return; }
                          here.empty();
                          handleNewTask(res, realNames, here);
                        }
                      );
                });
  if (!isCutTask) concreteAsmps.append(startCut);



  // Concrete conclusions
  var concreteAll    = $('<table/>');
  var concreteConc   = $('<td/>');
  concreteAll.append($('<tr/>').append([concreteConc]));

  inputMap[null] = { asmp: { dom: $('<div/>').hide() }
                   , conc: { dom: concreteAll
                           , body: concreteConc
                           }
                   };

  // Put the basic goal elements in the various holes.
  var goalInfos = {};
  jQuery.each(task.goals, function(unused, taskGoal) {
    goalInfos[taskGoal.id] =
      galoisRenderGoal(taskGoal, inputMap, concreteAsmps, goalInfos,
                                                          realNames, here)
  });

  // Make normal inputs into drop targets
  jQuery.each(task.inputs, function(unused, inp) {
    var id = inp.id;
    var i = inputMap[id];
    galoisMakeDropTarget(goalInfos, i, true /* are we an asmp? */);
    galoisMakeDropTarget(goalInfos, i, false);
    galoisRenderSuggestions(goalInfos, i);
  });

  // Make function post-conditions into drop targets.
  jQuery.each(task.calls, function(unused, call) {
    var id = call.id;
    var i = inputMap[id];
    galoisAddCallSolutions(goalInfos, i, call.initialSolutionId);
    if (!call.readOnly) {
      galoisAddNewPostHandlers(here, i);
      galoisMakeDropTarget(goalInfos, i, true /* are we an asmp? */);
    }
  });



  // Now arrange everying in a single container: a table with a single row

  var table = $('<table/>')
              .css('margin-left', '205px');
  var row = $('<tr/>');
  var inputsColumn = $('<td/>').css('vertical-align', 'top');
  table.append(row);
  row.append([inputsColumn, $('<td/>').append(concreteAsmpsBg)]);

  var asmpIsland = grassArea($(window).width() * 1 / 2, null, theme.asmpStyle);
  var concIsland = grassArea($(window).width() * 1 / 2, null, theme.inputStyle);

  inputsColumn.append([asmpIsland.dom, concIsland.dom]);

  jQuery.each(inputMap, function(ix,inp) {
    asmpIsland.mid.append(inp.asmp.dom.hide());
    concIsland.mid.append(inp.conc.dom.hide());
  });

  jQuery.each(task.graph, function(nodeIx, entry) {
    var fromInp = inputMap[entry.fromInputId];

    jQuery.each(entry.to, function(edgeIx, edge) {
      var inp   = inputMap[edge.inputId];
      var ginfo = goalInfos[edge.goalId];
      inp.asmp.dom.addClass(ginfo.goalClass);
      fromInp.conc.dom.addClass(ginfo.goalClass);
    });
  });


  // Now make the top-level menu.

  // Keyboard mode indicator
  var modeIndicator = $('<div/>').attr('id', 'mode_indicator').html('&nbsp;');
  var palette       = galoisRenderPalette(task.palette,realNames,here);


  var giveUp = $('<img/>')
               .attr('src', '/static/img/PlanetCute_PNG/Selector.png')
               .addClass('clickable')
               .css('position', 'fixed')
               .css('right', '1em')
               .css('bottom', '1em')
               .css('z-index', '20')
               .click(onDone('abandon'));





  var checkMethods = galoisRenderCheckModes();

  // Put everything togetether (except for the arrows).
  var dom = $('<div/>')
            .css('position', 'relative');

  concreteAsmps.prepend(freebies)

  var miniMap = $('<div/>')
                .addClass('mini_map')
                .css('position', 'fixed')
                .css('background-color', 'rgba(0,0,0,0.7)')
                .css('min-width','200')
                .css('width',    '200')
                .css('padding',  '5px')
                .css('left',     '0px')
                .css('top',      '180')
                .css('max-height', '700px')
                .css('overflow-y', 'scroll')
                .css('overflow-x', 'hidden');

  miniMap.hover ( function () { miniMap.css('width','auto');
                                miniMap.width(miniMap.width() + 50);
                              }
                , function () { miniMap.css('width', '200px'); }
                )

  dom.append([ modeIndicator, checkMethods, giveUp
             , palette
             , table
             , miniMap ]);


  return { dom: dom
         , drawGraph: function () {
             drawMiniMap(task.graph, inputMap, goalInfos, miniMap,
                          checkMethods,  here
                        , onDone('keep'), realNames);
             galoisPrepareKeyboard();
           }
         };
}

var curGInfo = null;      // Which goal is currently selected.
var mineBlock = null;


// Assumes at least one goal.
function drawMiniMap (graph, inputMap, goalInfos, me, checkMethods, here, onDone, realNames) {
  var curVisAsmp;         // Which asmp input are we looking at.


  var anchors = galoisGetAnchors(graph);

  jsPlumb.reset();
  // Defaults for drawing the arrwos
  jsPlumb.importDefaults({
     ConnectionsDetachable: false,
     ConnectionOverlays: [ ['Arrow', { location: 1, width: 15 
                                     , paintStyle: { fillStyle: '#fff' }
                                     }
                           ]
                         , [ 'Custom',
                              { location: [0.5]
                              , id: 'char'
                              , create: function(comp) {
                              return $('<img/>')
                                      .attr('src', 'img/PlanetCute_PNG/Character_Horn_Girl_cropped.png')
                                      .attr('width', '32px')
                                      .attr('height','64px');
                                }
                             } ]
                         ],
     Connector: [ 'Flowchart', { cornerRadius: 2, stub: 25, gap: 10 } ],
     Container: me,
     PaintStyle: { lineWidth: 10, strokeStyle: 'blue' }
  });


  // Make the "islands" of the mini-map.
  var inputCells = {};
  jQuery.each(graph, function(nodeIx, entry) {
    var theInfo = anchors[nodeIx];

    var w = Math.max( 128, theInfo.minWidth * 1.5);

    var bg;
    var inp = inputMap[entry.fromInputId];
    if (entry.fromInputId === null) bg = 'concrete'; else
    if (inp.tag === 'call')         bg = 'call'; else
    if (inp.input.isPrecondition)   bg = 'precondition'; else
                                    bg = 'loop';

    var bg = miniMapPic[bg];

    var bgH = (w / bg.width) * bg.height;
    var h   = Math.max( bgH, theInfo.minHeight * 1.5);

    var block   = $('<div/>')
                  .css('position', 'relative')
                  .addClass('mini_map')
                  .css('width', w + 'px')
                  .css('height', h + 'px');

    if (nodeIx !== (graph.length - 1)) {
      block.css('margin-top', '5em');
    }

    block.css('background-image', 'url("/static/img/' + bg.url + '.png")')
         .css('background-size', w + 'px ' + bgH + 'px')
         .css('background-repeat', 'no-repeat');

    inputCells[entry.fromInputId] = { dom: block };

    block.addClass('clickable')
         .click(function () { switchToAsmp(entry.fromInputId); });

    me.prepend(block);
    if (nodeIx === 0)
      curGInfo = goalInfos[entry.to[0].goalId];

  });

  // Add gem and finish button girl
  jQuery.each(inputMap, function (ix,i) {
    if (i.tag === 'normal' && i.input.isPrecondition) {
      var doneChar =
          $('<img/>')
          .attr('id', 'finish_char')
          .attr('src', 'img/PlanetCute_PNG/Gem_Orange.png')
          .width('64px')
          .height('96px')
          .hide()
          .addClass('clickable')
          .click(onDone);

      inputCells[ix].dom.append([doneChar]);
      mineBlock = inputCells[ix].dom;
      return false; // exit each loop
    }
  });


  jQuery.each(graph, function(nodeIx, entry) {
    var theInfo      = anchors[nodeIx];
    var theseAnchors = theInfo.anchors;
    var src          = inputCells[entry.fromInputId];

    jQuery.each(entry.to, function(edgeIx, edge) {
      var ginfo = goalInfos[edge.goalId];
      var tgt   = inputCells[edge.inputId];

      var con = jsPlumb.connect(
        { source: src.dom
        , target: tgt.dom
        , endpoints: [  ginfo.goalOptSourceTask === null ?
                           'Blank'
                        : ['Image', { src: '/static/img/icons/cross.png'
                                 } ]

                     ,  ['Image', { src: '/static/img/icons/lock.png'
                        } ]

                      ]
        , cssClass: ginfo.goalClass + ' goal_arrow'
        , anchors: theseAnchors[edgeIx]
        });

      var inp = inputMap[edge.inputId];
      var bg;
      if (inp.tag === 'call')
        bg = 'call1.jpg';
      else if (inp.tag === 'normal' && inp.input.isPrecondition)
        bg = 'precondition.jpg';
      else
        bg = 'loop.png';

      bg = '/static/img/VA/Doors/' + bg;

      checkMethods.append($('<div/>')
                  .addClass('goal_elem')
                  .addClass(ginfo.goalClass)
                  .css('position','relative')
                  .css('width',  '200px')
                  .css('height', '80px')
                  .css('background-repeat', 'no-repeat')
                  .css('background-size', '200px 80px')
                  .css('background-image', 'url("' + bg + '")')
                  .css('overflow', 'hidden')
                  .click(function() {
                    if (curGInfo !== null) galoisUpdateGoalStatus(ginfo, 'full')
                   })
                  .append($('<img/>')
                          .css('position','absolute')
                          .attr('src','/static/img/VA/Doors/closed.png')
                          .css('width','200px')
                          .css('height','80px')
                          .addClass(ginfo.goalClass)
                          .addClass('status')
                          .addClass('unproved')
                          )
                 .hide());


      con.bind('click', function(conn) {
        $('.goal_elem').hide();
        if (curGInfo !== null) {
          $('.' + curGInfo.goalClass).removeClass('selected');
          curGInfo.visible = false;
          repaintGoalStatus(curGInfo); // to make line thin
          if (curGInfo.provedBy !== null)
            $('#' + curGInfo.provedBy).removeClass('is_prover');
        }

        curGInfo = goalInfos[edge.goalId];
        switchToCurGoal();
      });

      con.endpoints[1].bind('click', function() {
        galoisUpdateGoalStatus(goalInfos[edge.goalId], null);
      });

      if (ginfo.goalOptSourceTask !== null) {
        con.endpoints[0].bind('click', function() {
          setTimeout(startTask(ginfo.goalOptSourceTask, realNames, here)
                    , 0);
        });
      }

      ginfo.goalConnection = con;

      repaintGoalStatus(ginfo);
    });

    $('.goal_elem').hide();
  });

  switchToCurGoal();
  return;


  function switchToAsmp(n) {
    if (curVisAsmp !== undefined) {
      inputMap[curVisAsmp].asmp.dom.hide();
      inputCells[curVisAsmp].dom.removeClass('mini_map_sel');
    }
    curVisAsmp = n;
    inputMap[curVisAsmp].asmp.dom.show();
    inputCells[curVisAsmp].dom.addClass('mini_map_sel');
  }

  function switchToCurGoal() {
    if (curGInfo === null) return;

    // Figure out start and end inputs.
    var fromInput;
    var toInput;
    jQuery.each(graph, function(ix,entry) {
      var notFound = true;
      fromInput = entry.fromInputId;
      jQuery.each(entry.to, function(ix,edge) {
        if (curGInfo.goalId === edge.goalId) {
          toInput = edge.inputId;
          notFound = false;
          return false;
        }
      });
      return notFound;
    });
    switchToAsmp(toInput);

    // Hide and show goal specific info
    var thingsToShow = $('.' + curGInfo.goalClass);
    thingsToShow.addClass('selected').show();
    thingsToShow.find('.holesimp').hide();
    curGInfo.redrawAsmps();

    curGInfo.visible = true;
    repaintGoalStatus(curGInfo);

    $('#finish_char').hide();
  }

}




function makeAsmpToggler(goalClass,vars) {

  var filterClass = 'filtering_conc_asmp';
  var me = $('<div/>')
           .addClass('goal_elem')
           .addClass(goalClass)
           .hide();
  var filters = [];

  function redraw() {
    var allAsmp = $('.' + goalClass + '.conc_asmp');

    allAsmp.filter(function() { return !($(this)
                                         .parent()
                                         .hasClass('freebies')) })
           .hide()

    var cl = '*';
    jQuery.each(filters, function(vid,filter) {
      if (filter === true) {
          cl = cl + '.' + hasVarClass(vid);
      }
    });

    var vis = allAsmp.filter(cl);

    var orCl = '';
    jQuery.each(vis,function(ix,thing) {
      jQuery.each(vars, function(ix,v) {
        var c = hasVarClass(v.id);
        if ($(thing).hasClass(c)) {
          if (orCl !== '') orCl += ',';
          orCl += '.conc_asmp_btn.' + c;
        }
      });
    });

    vis.add(allAsmp.filter(orCl)).show();
  }

  jQuery.each(vars, function(ix,v) {
    var btn = renderVar(v.id)
            .css('margin', '5px')
            .addClass(goalClass)
            .addClass(hasVarClass(v.id))
            .addClass('conc_asmp')
            .addClass('conc_asmp_btn')
            .addClass('clickable');

    filters[v.id] = btn.hasClass(filterClass);

    btn.click(function () {
      btn.toggleClass(filterClass);
      filters[v.id] = btn.hasClass(filterClass);
      redraw();
    });

    me.append(btn);
  });

  return { dom: me, redraw: redraw };
}


// Compute locations of arrows on the boxes, so they don't overlap too much.
// Also, we compute minimum dimensions for the boxes, so that we can accomodate
// the arrows.
function galoisGetAnchors(graph) {

  var ixMap = {};
  jQuery.each(graph, function(ix, entry) {
    ixMap[entry.fromInputId] = { ix: graph.length - 1 - ix
                                              // our vertical position
                               , left: 0      // next left position
                               , right: 0     // next right position
                               , top: 0       // next top position
                               , bottom: 0    // next bottom position
                               };
  });


  var arrows = [];

  jQuery.each(graph, function(ix, entry) {
    var srcState = ixMap[entry.fromInputId];
    var srcIndex = srcState.ix;
    var es = [];

    entry.to.sort(function(a,b) {
      return ixMap[a.inputId].ix - ixMap[b.inputId].ix;
    });


    jQuery.each(entry.to, function(ix, edge) {
      var tgtState = ixMap[edge.inputId];
      var tgtIndex = tgtState.ix;

      function mk(dir,st) {
        var v;
        switch(dir) {
          case 'Bottom': v = ++st.bottom; break;
          case 'Top':    v = ++st.top;    break;
          case 'Left':   v = ++st.left;   break;
          case 'Right':  v = ++st.right;  break;
        }
        return [ dir, st, v ];
      }

      function link(dir1, dir2) {
        // We do them backwards, so that loops point backwards.
        var snd = mk(dir2, tgtState);
        var fst = mk(dir1, srcState);
        es.push([ fst, snd ]);
        return true;
      }

      if (srcIndex + 1 === tgtIndex)    { return link('Bottom', 'Top');    }
      if (srcIndex    === tgtIndex + 1) { return link('Top',    'Bottom'); }
      if (srcIndex    <   tgtIndex)     { return link('Left',   'Left');   }
      if (srcIndex    >=  tgtIndex)     { return link('Right',  'Right');  }
    });

    arrows.push( { state: srcState, edges: es });
  });

  // This is jsPlumb's way of specifying "anchors"---where arrows attach.
  // The format is [x,y,dx,dy]: `x` and `y` vary between 0 and 1, and indicate
  // the starting position of an arrow, while `dx` and `dy` are for its initial
  // orientation.
  function makeAnchor(obj) {
    switch (obj[0]) {
      case 'Bottom': return [ obj[2] / (obj[1].bottom + 1),    1,  0,  1 ];
      case 'Top':    return [ obj[2] / (obj[1].top + 1),       0,  0, -1 ];
      case 'Left':   return [ 0, obj[2] / (obj[1].left + 1),      -1,  0 ];
      case 'Right':  return [ 1, obj[2] / (obj[1].right + 1),      1,  0 ];
    }
  }

  // Once we know how many arrows are attached to each box, we can compute
  // the corresponding anchors, and box dimensions.
  var anchors = [];
  jQuery.each(arrows, function(nodeIx, es) {
    var xs = [];
    jQuery.each(es.edges, function(edgeIx, arr) {
      xs[edgeIx] = [ makeAnchor(arr[0]), makeAnchor(arr[1]) ];
    });
    var state = es.state;
    anchors[nodeIx] = { anchors: xs
                      , minWidth:  25 * Math.max(state.top, state.bottom, 1)
                      , minHeight: 25 * Math.max(state.left, state.right, 1)
                      };
  });

  return anchors;
}


function galoisRenderParamBox(areas, hname, paramIx, info) {

  var a = areas[info.purpose];
  if (a === undefined) {
    a = {};
    areas[info.purpose] = a;
  }

  var b = a[info.when];
  if (b === undefined) {
    b = [];
    a[info.when] = b;
  }

  var paramBox = $('<td/>');
  var toggler  = $('<td/>')
                 .addClass('param_button')
                 .addClass('goal_elem');
  var pclass = paramClass(hname,paramIx);
  renderToggler(toggler, false, [pclass]);

  b.push({valueBox: paramBox, togglerBox: toggler});

  return { dom: paramBox        // insert param expressions here
         , togglerDom: toggler  // toggle using this
         , type: info           // type and stuff (not sure if used)
         };
}


function galoisRenderParamAreas(areas) {

  function areaIx(a) {
    switch (a) {
      case 'special': return 0;
      case 'global':  return 1;
      case 'normal':  return 2;
      case 'local':   return 3;
      default:        return 4;
    }
  }

  var sort_this = [];
  jQuery.each(areas, function(area,things) {
    sort_this.push( [ area, things ] );
  });

  function compare(x,y) { return areaIx(x[0]) - areaIx(y[0]); }

  var res = {};
  jQuery.each(sort_this.sort(compare), function(ix,things) {
    var container = $('<td/>')
                    .addClass('goal_elem');
    container.append(galoisRenderParamArea(things[0],things[1]));
    res[things[0]] = container;
  });

  return res;
}


// things : [ { valueBox: dom, togglerBox: dom } ]
function galoisRenderParamThings(things) {
  var perRow = 10;
  var rows = Math.ceil(things.length / perRow);
  var me = $('<table/>');
  var i;
  var j;
  for (i = 0; i < rows; ++i) {
    var r1 = $('<tr/>');
    var r2 = $('<tr/>');
    for (j = 0; j < perRow; ++j) {
      var ix = i * perRow + j;
      if (ix < things.length) {
        var thing = things[ix];
        r1.append(thing.valueBox);
        r2.append(thing.togglerBox);
      } else {
        r1.append($('<td/>'));
        r2.append($('<td/>'));
      }
    }
    me.append([r1,r2]);
  }
  return me;
}


// area : { start: [_], here: [_] }
// see also: galoisRenderParamThings
function galoisRenderParamArea(name,area) {


  var open = $('<img/>')
             .attr('src', 'img/PlanetCute_PNG/Chest_Open.png')
             .attr('title', name)
             .width('20px');

  var closed = $('<img/>')
             .attr('src', 'img/PlanetCute_PNG/Chest_Closed.png')
             .attr('title', name)
             .css('margin', '0')
             .width('40');

  var hidden;

  var lab = $('<div/>')
           .append(open)
           .append(closed)
           .addClass('clickable')
           .click(function () {
              if (hidden) openChest(); else closeChest();
            });

  var me = $('<div/>')
           .css('margin', '1em')
           .css('display', 'inline-block')
           .css('padding', '2px')
           .append(lab);

  function openChest() {
    jQuery.when( lab.siblings().show()
               , open.show()
               , closed.hide()
               ).done(function() {

                  me.css('background-color', 'rgba(40,40,40,0.5)')
                    .css('border', '1px solid black');
                  hidden = false;
                 });
  }

  function closeChest () {
    jQuery.when( lab.siblings().hide()
               , closed.show()
               , open.hide()
               ).done(function () {
                       me.css('background-color', 'rgba(40,40,40,0)')
                         .css('border', '0');
                        hidden = true;
                      });
  }


  if (area.start !== undefined) {
    me.append(galoisRenderParamThings(area.start))
  }

  if (area.here !== undefined) {
    if (area.start !== undefined) {
      var it = $('<hr/>')
               .css('border', '1px solid black');
      me.append(it);
    }

    me.append(galoisRenderParamThings(area.here));
  }

  if (name === 'normal' ||
      name === 'local'  ||
      name === 'return') openChest(); else closeChest();

  return me;
}


function renderNormalInputInner(inputId,inputParams) {

  // Setup parameters
  var paramRow    = $('<tr/>');
  var buttonCell  = $('<td/>')
                  .attr('rowspan', 2);

  paramRow.append(buttonCell);

  var params  = [];

  var hname   = hole_name(inputId, 'iNormal');
  var areas   = {};

  jQuery.each(inputParams, function (paramIx, paramInfo) {
    params[paramIx] = galoisRenderParamBox(areas,hname,paramIx,paramInfo);
  });

  var paramMap = galoisRenderParamAreas(areas);
  var paramNum = 0;
  jQuery.each(paramMap, function(a,td) {
    paramRow.append(td);
    ++paramNum;
  });


  // Setup the body
  var bodyRow  = $('<tr/>');
  var body     = $('<td/>')
                 .attr('colspan', 1 + paramNum)
                 .css('min-width', '5em')
                 .addClass('normal_definition');

  bodyRow.append(body);


  // Put it all together
  var dom      = $('<table/>')
                 .addClass('goal_elem')
                 .append(paramRow)
                 .append(bodyRow);

  return { dom:        dom
         , body:       body
         , params:     params
         , areas:      paramMap
         , buttonCell: buttonCell
         };
}


function renderNormalInput(input) {
  var asmp = renderNormalInputInner(input.id, input.params);
  var conc = renderNormalInputInner(input.id, input.params);
  return { input: input
         , tag:   'normal'
         , asmp:  asmp
         , conc:  conc
         };
}



function renderCallInputInner(input, inAsmp) {

  var dom         = $('<table/>').addClass('goal_elem');
  var firstRow    = $('<tr/>');
  var paramsRow   = $('<tr/>');
  var bodiesRow   = $('<tr/>');

  var buttonCell  = $('<td/>').attr('rowspan', 2);

  paramsRow.append(buttonCell)

  dom.append(firstRow)
     .append(paramsRow)
     .append(bodiesRow);

  var preBody  = $('<td/>');
  var postBody = $('<td/>');

  bodiesRow.append(preBody)
           .append(postBody);

  var callHeaderCell = $('<td/>').attr('colspan', 1 + input.preParams.length
                                                    + 1
                                                    + input.postParams.length)
                                 .text(input.function);
  firstRow.append(callHeaderCell);


  if (inAsmp && !input.readOnly) {
    var newPostButton = $('<input/>').attr('type','button').val('new postcondition');
    callHeaderCell.append(newPostButton);
  }


  var preAreas = {};
  var preParams = [];
  var hname = hole_name(input.id, 'iPre');
  jQuery.each(input.preParams, function(paramIx, paramInfo) {
    preParams[paramIx] =
      galoisRenderParamBox(preAreas, hname, paramIx, paramInfo );
  });

  var postAreas = {};
  var postParams = [];
  var hname = hole_name(input.id, 'iPost');
  jQuery.each(input.postParams, function(paramIx, paramInfo) {
    postParams[paramIx] =
      galoisRenderParamBox(postAreas, hname, paramIx, paramInfo );
  });

  var preMap = galoisRenderParamAreas(preAreas);
  var preNum = 0;
  jQuery.each(preMap, function(a,td) {
    paramsRow.append(td);
    ++preNum;
  });
  preBody.attr('colspan', preNum);

  var separatorCell = $('<td/>').attr('rowspan',3)
                       .html('&nbsp;')
                       .css('background-color', 'black');
  paramsRow.append(separatorCell);

  var postMap = galoisRenderParamAreas(postAreas);
  var postNum = 0;
  jQuery.each(postMap, function(a,td) {
    paramsRow.append(td);
    ++postNum;
  });
  postBody.attr('colspan', postNum);

  return { dom:        dom
         , tag:        'call'
         , pre:        { body: preBody,  params: preParams, areas: preMap }
         , post:       { body: postBody, params: postParams, areas: postMap }
         , buttonCell: buttonCell
         , newPost:    newPostButton
         };
}


function renderCallInput(input) {
  var asmp = renderCallInputInner(input,true);
  var conc = renderCallInputInner(input,false);
                              // has more than needed, but should
                                          // be ok
  return { input: input
         , tag:   'call'
         , asmp:  asmp
         , conc:  conc
         }
}




function galoisRenderGoal( taskGoal, inputMap, concreteAsmps, goalInfos, realNames, here ) {

  var goal = taskGoal.goal;

  var varTys     = {};
  var qVarColors = {};
  jQuery.each(goal.vars, function(unused, v) {
    varTys[v.id]     = v.type;
    qVarColors[v.id] = 'red';   // XXX: shouldn't really use this.
  });



  var info = { gId:        taskGoal.id
             , varTys:     varTys
             , qVarColors: qVarColors
             , collapse:   true
             , toggleVars:    makeVarClassDB(goal)
             , clickDispatch: galoisExpressionClicked
             , goalInfos: goalInfos
             , inputContext: null
             , realNames: realNames
             , here: here
             };


  // All bits of this goal are tagged with this class, so that we
  // can conveniently hide/show them.
  var goalClass = 'goal_' + taskGoal.id;

  var asmpTogglers = makeAsmpToggler(goalClass, goal.vars);
  concreteAsmps.append(asmpTogglers.dom);

  jQuery.each(goal.asmps, function(asmpIndex, topExpr) {
    var asmpIsVisible = goal.visible.indexOf(asmpIndex) !== -1;
    var localInfo = jQuery.extend({}, info, {collapse: !asmpIsVisible});
    galoisRenderPred(localInfo, inputMap, topExpr, concreteAsmps, goalClass);
  });

  galoisRenderPred(info, inputMap, goal.conc, null, goalClass);

  return { goalId: taskGoal.id
         , goalInfo: info
         , goalClass: goalClass
         , redrawAsmps: asmpTogglers.redraw
         , visible: false
         , goalStatus: goal.proved ? 'proved' : 'unproved'
         , provedBy: null
         , goalConnection: null  // setup later
         , goalOptSourceTask: taskGoal.sourceTask
         }
}



function galoisRenderPred(info,inputMap, topExpr, concreteAsmps, goalClass) {
  var inAsmp = concreteAsmps !== null;
  var expr = topExpr.expr.struct;

  if (expr.tag === 'hole') {

    // The input structure
    var renderedInputDetails = inputMap[expr.inputId];
    var inpLoc = inAsmp ? renderedInputDetails.asmp
                        : renderedInputDetails.conc;


    var paramLoc;   // Parameters go here
    var bodyLoc;    // The hole-body goes here
    var paramAreas; // The varioud paramter groups
    var buttonLoc = inpLoc.buttonCell;  // The undo button
    switch (expr.inputType) {
      case 'iNormal':
        paramLoc    = inpLoc.params;
        paramAreas  = inpLoc.areas;
        bodyLoc     = inpLoc.body;
        break;
      case 'iPre':
        paramLoc    = inpLoc.pre.params;
        paramAreas  = inpLoc.pre.areas;
        bodyLoc     = inpLoc.pre.body;
        break;
      case 'iPost':
        paramLoc    = inpLoc.post.params;
        paramAreas  = inpLoc.post.areas;
        bodyLoc     = inpLoc.post.body;
        break;
      default: console.log('unexpected parameter type', expr.inputType);
    }

    bodyLoc.addClass(goalClass);


    // The "undo/suggestions" button
    buttonLoc.addClass(goalClass);

    // Fill-in the parameters.
    var hname = hole_name(expr.inputId, expr.inputType);
    var hinfo = jQuery.extend({}, info, { taskPath: topExpr.taskPath });
    jQuery.each(expr.params, function(ix, param) {
      var pclass = paramClass(hname, ix);
      paramLoc[ix].dom.append( renderExpr(hinfo, param, false)
                               .addClass(pclass)
                               .addClass('goal_elem')
                               .addClass('param_invisible')
                               .addClass(goalClass)
                             );
      paramLoc[ix].togglerDom.addClass(goalClass);
      paramAreas[paramLoc[ix].type.purpose].addClass(goalClass);
    });

    // Add hole definition, if any
    if (expr.def !== null) {
      var definfo = jQuery.extend({}, hinfo,
                       { inputContext:
                           { inputInfo: renderedInputDetails
                           , inAsmp: inAsmp
                           , inputType: expr.inputType
                           }
                       , collapse: false
                       });


    var simpInfo = jQuery.extend({}, definfo, {taskPath: null})
    var es = renderExpr(simpInfo, expr.simp, false)
            .addClass('goal_elem')
            .addClass('holesimp')
            .addClass(goalClass)
            .hide()

    bodyLoc.append(
       renderTopExpr(definfo, expr.def, true)
       .addClass('goal_elem')
       .addClass('holepred')
       .addClass(goalClass)
       ).append(es)
    }


  } else /* not a hole */ {

    // A concrete assumption
    if (inAsmp) {

      var otherClick = info.clickDispatch

      // What to do when clicking on an assumption
      function whenClicked(info, e, rendered_e, state) {
        if (state === 'freebie' && e.path === "1") {
          var p = rendered_e.parent()
          if (p.hasClass('freebies')) {
            // hide asmp
            concreteAsmps.append(rendered_e)
            markHidden(info.taskPath, e.path);
            invalidateGoals(info.goalInfos, [info.gId]);
            return false;
          } else {
            // show asmp
            concreteAsmps.find('.freebies').append(rendered_e)
            markRevealed(info.taskPath, e.path);
            return false;
          }
        } else
          return otherClick(info, e, rendered_e, state)
      }

      var ainfo = jQuery.extend({}, info, { clickDispatch:  whenClicked })
      var e = renderTopExpr(ainfo, topExpr, true)
             .addClass('goal_elem').addClass(goalClass);
      concreteAsmps.append(e);
      jQuery.each(topExpr.expr.varIds, function(ix,varid) {
        e.addClass(hasVarClass(varid))
         .addClass('conc_asmp');
      });

    // A concrete conclusion
    } else {
      var concrete = inputMap[null];
      info = jQuery.extend({}, info, { collapse: false });
      var e = renderTopExpr(info, topExpr, true)
             .addClass('goal_elem').addClass(goalClass);
      concrete.conc.body.append (e);
    }
  }
}

function hasVarClass(varid) { return 'has_var_' + varid; }

function galoisRenderCheckModes() {
  var method_num = 1;

  var proverPics = { simple: '/static/img/VA/monsters/05.png'
                   , altergo: '/static/img/VA/monsters/28.png'
                   , cvc4: '/static/img/VA/monsters/39.png'
                   , bits: '/static/img/VA/monsters/22.png'
                   };

  function opt(x) {
    return $('<img/>').attr('src', proverPics[x])
           .attr('id', x)
           .attr('width',  '48px')
           .attr('height', '48px')
           .attr('title', x)
           .click(function () {
              if (curGInfo === null) return;
              galoisUpdateGoalStatus(curGInfo,x);
           });
  }

  var provers = [ 'simple', 'altergo', 'cvc4', 'bits' ];

  var div = $('<div/>')
            .css('z-index','5')
            .css('position','fixed')
            .css('color', 'orange')
            .css('background-color', 'rgba(50,50,50,0.8)')
            .css('padding', '2px')
            .css('margin', '2px');

  jQuery.each(provers, function(ix,p) {
    div.append(opt(p));
  });

  return div;

}


function galoisUpdateGoalStatus(ginfo, how) {
  ginfo.goalStatus = 'proving';
  if (ginfo.provedBy !== null) {
    $('#' + ginfo.provedBy).removeClass('is_prover');
  }
  ginfo.provedBy   = null;
  repaintGoalStatus(ginfo);

  var checkMode = how === null ? 'full' : how;

  var time = 1;

  galoisPost
    ( '/play/updateGoal'
    , { goalid: ginfo.goalId
      , mode: checkMode
      , time: time
      }
    , function (res) {
        if (res.error) { alert(res.error_message); return; }
        ginfo.goalStatus = res.result;
        ginfo.provedBy   = res.prover;
        repaintGoalStatus(ginfo);
        checkFinished();
      }
    );
}


function repaintGoalStatus(ginfo) {
  var stat = $('.status.' + ginfo.goalClass);
  stat.removeClass('proved unproved proving')
      .addClass(ginfo.goalStatus);

  var color;
  var bg;
  switch (ginfo.goalStatus) {
    case 'proved':
        color = 'green';  bg = 'lock_unlock';
        if (ginfo.provedBy === 'simple') color = 'lime';
        break;
    case 'proving':  color = 'yellow'; bg = 'key';  break;
    case 'unproved': color = 'red';    bg = 'lock'; break;
    case 'failed':   color = 'gray';   bg = 'lock'; break;
  }

  if (ginfo.provedBy !== null) {
    $('#' + ginfo.provedBy).addClass('is_prover');
  }

  var width = ginfo.visible ? '25' : '10';
  var conn = ginfo.goalConnection;
  var srcEndpoint = conn.endpoints[1];
  srcEndpoint.setImage('/static/img/icons/' + bg + '.png');
  conn.setPaintStyle({ lineWidth: width, strokeStyle: color });
  conn.getOverlay('char').setVisible(ginfo.visible);
}


function invalidateGoals(goalInfos, gids) {
  jQuery.each(gids, function(ix,gid) {
    var ginfo = goalInfos[gid];
    ginfo.goalStatus = 'unproved';
    if (ginfo.provedBy !== null)
      $('#' + ginfo.provedBy).removeClass('is_prover');
    ginfo.provedBy = null;
    repaintGoalStatus(ginfo);
   });
  checkFinished();
}


function checkFinished() {

  var hasUnproved = $('.unproved').length != 0;
  var hasProving  = $('.proving' ).length != 0;
  var finish_char = $('#finish_char');

  if (hasUnproved || hasProving) {
    finish_char.hide();
  } else {
    finish_char.show();
  }
}




function galoisMakeDropTarget(goalInfos, inputInfo, inAsmp) {
  var thing = inputInfo.tag === 'normal'
            ? (inAsmp ? inputInfo.asmp.body : inputInfo.conc.body)
            : inputInfo.asmp.post.body;
  thing.droppable(
    { tolerance: 'pointer'
    , hoverClass: 'drop-hover'
    , drop: function (ev, ui) {
        var iPath = ui.helper.data('storm-drag');
        if (iPath === undefined) return;

        thing.effect('highlight');
        galoisPost ( '/play/addToHole'
                    , { taskpath: JSON.stringify(iPath.task)
                      , exprpath: JSON.stringify(iPath.expr)
                      , inputid:  inputInfo.input.id
                      , inAsmp: inAsmp
                      }
                    , galoisHandleNewInputResponse (goalInfos, inputInfo)
                    );
      }
    });
}

function galoisHandleNewInputResponse(goalInfos, inputInfo) {
  return function (res) {
    if (res.error) { alert(res.error_message); return; }
    if (res.changed === null) { return; }
    var inputType = inputInfo.tag === 'normal' ? 'iNormal' : 'iPost';

    var msg = 'Unknown';
    if (mineBlock !== null) {
      if (res.invalidPre === null)
        { msg = 'OK'; mineBlock.css('opacity', '1'); }
      else {
        mineBlock.css('opacity', '0.4');
        var msg = 'Unknown';
        switch (res.invalidPre.reason) {
          case 'asserted_false': msg = 'Asserted false!'; break;
          case 'contains_casts':
            var c = res.invalidPre.casts;
            msg = c + ' cast' + (c == 1 ? ' is' : 's are') + ' still present.';
            break;
        }
      }
      mineBlock.attr('title',msg);
    }

    galoisFillInput(goalInfos, inputInfo, inputType, res.holeExprs);

    invalidateGoals(goalInfos, res.invalidatedGoalIds);
  };
}

function galoisFillInput(goalInfos, inpInfo, inputType, insts) {

  function getBody(inAsmp) {
    var loc = inAsmp ? inpInfo.asmp : inpInfo.conc;
    if (inputType === 'iNormal') return loc.body;
    if (inputType === 'iPre')    return loc.pre.body;
    if (inputType === 'iPost')   return loc.post.body;
    console.log('unknown input type when `getBody`');
  }

  // First clear body elements
  getBody(true).empty();
  getBody(false).empty();

  // Render each instantiation
  jQuery.each(insts, function(unused, inst) {
    var ginfo = goalInfos[inst.goalId];
    var info = jQuery.extend( {}
                            , ginfo.goalInfo
                            , { collapse: false
                              , inputContext:
                                  { inputInfo: inpInfo
                                  , inAsmp: inst.inAsmp
                                  , inputType: inputType
                                  , input: inpInfo.input
                                  }
                              });

    var e = renderTopExpr(info, inst.inst, true)
            .addClass('goal_elem')
            .addClass('holepred')
            .addClass(ginfo.goalClass);

    var simpInfo = jQuery.extend({}, info, {taskPath: null});
    var es = renderExpr(simpInfo, inst.simp.expr, false)
            .addClass('goal_elem')
            .addClass('holesimp')
            .addClass(ginfo.goalClass)
            .hide();
    if (!ginfo.visible) e.hide();
    else { e.addClass('selected'); es.addClass('selected'); }

    getBody(inst.inAsmp).append(e,es);
  });
}


click_modifier_state = null;

indicator_loaded = false;

function galoisPrepareKeyboard () {
  if (indicator_loaded) {
    return;
  }
  indicator_loaded = true;

  $(document).keydown(function() {

    var cell = $('#mode_indicator');
    if (cell === undefined) return;

    var keycode = event.which;

    switch(keycode) {

      case 67: // C
        cell.text('case');
        click_modifier_state = 'case';
        cell.addClass('mode_active');
        break;

      case 68: // D
        cell.text('delete');
        click_modifier_state = 'delete';
        cell.addClass('mode_active');
        break;

      case 70: // F
        cell.text('freebie');
        click_modifier_state = 'freebie';
        cell.addClass('mode_active');
        break;

      case 71: // G
        cell.text('grab');
        click_modifier_state = 'grab';
        cell.addClass('mode_active');
        break;

      case 82: // R
        cell.text('rewrite');
        click_modifier_state = 'rewrite';
        cell.addClass('mode_active');
        break;

      case 81: // Q
        cell.addClass('mode_active')
            .text('quick');
        click_modifier_state = 'quick';
        break;

      case 83: // S
        cell.text('simplified');
        cell.addClass('mode_active');
         $('.selected.holepred').hide();
         $('.selected.holesimp').show();
        break;

      case 85: // U
        cell.text('ungrab');
        cell.addClass('mode_active');
        ungrabExpression();
        break;

      case 86: // V
        cell.text('occurs');
        click_modifier_state = 'occurs';
        cell.addClass('mode_active');
        break;

      case 88: // X
        cell.text('hide');
        click_modifier_state = 'hide';
        cell.addClass('mode_active');
        break;

      default:
        cell.text(keycode);
        click_modifier_state = keycode.toString();
        break;
    }
  });

  $(document).keyup(function() {


     switch(event.which) {

       case 90: // Z
         $('.input_box').fadeToggle();
         break;
       case 83: // S
         $('.selected.holesimp').hide();
         $('.selected.holepred').show();
         break;
      }

    click_modifier_state = null;
    $('#mode_indicator').removeClass('mode_active').html('&nbsp;');
  });
}



function galoisExpressionClicked(info, e, rendered_e, clickModifierState) {

    var taskPath = info.taskPath;
    var exprPath = e.path;

    if (taskPath === undefined) {
      console.log('Expression had an undefined taskPath');
      return true;
    }

    if (taskPath === null) {
      // These are unclickable expressions,
      // propogate the click up to the containing element.
      return true;
    }

    switch (clickModifierState) {

    case 'case':
      galoisPost
        ( '/play/split'
        , { taskpath: JSON.stringify(taskPath)
          }
        , function(task) { handleNewTask(task, info.realNames, info.here); }
        );
      return false;

    case 'rewrite':
      if (taskPath.tag === 'template') {
        galoisPost
              ( '/play/viewRewrites'
              , { taskpath: JSON.stringify(taskPath)
                , exprpath: JSON.stringify(exprPath)
                }
              , renderRewriteQuery(info, taskPath, exprPath, rendered_e)
              );
      }
      return false;

    case 'delete':
      if (taskPath.tag === 'template') {
        galoisPost
              ( '/play/deleteInput'
              , { taskpath: JSON.stringify(taskPath)
                , exprpath: JSON.stringify(exprPath)
                }
              ,
               galoisHandleNewInputResponse
                  ( info.goalInfos
                  , info.inputContext.inputInfo
                  )
              );
      }
      return false;

    case 'grab':

      galoisPost
        ( '/play/grabInput'
        , { taskpath: JSON.stringify(taskPath)
          , exprpath: JSON.stringify(exprPath)
          }
        , handleGrabInputResponse(rendered_e)
        );

      return false;

    default:
      return true;
    }
}


function ungrabExpression() {
  galoisPost
    ( '/play/ungrab'
    , { }
    , function() {}
    );
  $('.grabbed').removeClass('grabbed');
}


function handleGrabInputResponse(rendered_e) {
  return function(res) {
    if (res.expr !== "") {
      $('.grabbed').removeClass('grabbed');
      rendered_e.addClass('grabbed');
    }
  }
}





function renderRewriteQuery(info, taskPath, exprPath, rendered_e) {
  return function (res) {
    function cleanup() { $('.rewriteMenu').remove(); }

    cleanup();

    var ul = $('<ul/>').addClass('rewriteMenu');
    var preview = $('<div/>')
                  .addClass('rewriteMenu')
                  .css('border', '4px solid orange')
                  .css('background-color', 'white')
                  .css('box-shadow', '2px 2px 10px 4px #666')
                  .css('position', 'absolute')
                  .css('min-height', '1em')
                  .css('min-width', '8em');


    ul.append($('<li/>')
               .click(cleanup)
               .append($('<i/>').text('No rewrite')));

    jQuery.each(res, function(ix,match) {

      var descTable = $('<table/>');
      var row1 = $('<tr/>')
      var row2 = $('<tr/>');
      descTable.append([row1,row2]);
      row1.append($('<th/>').text(match.name));
      row1.append($('<td/>').append($('<i/>').text(match.effect)));
      row2.append($('<td/>')
                   .attr('colspan',2)
                   .append(renderExpr(info, match.expr, false)));

      if (match.side !== null) {
        row1.append($('<th/>').addClass('sideCondition')
                              .text('Side condition'));
        row2.append($('<td/>').addClass('sideCondition')
                .append(renderExpr(info, match.side,  false)));
      }
      preview.append(descTable.hide());

      var effectShort = '? ';
      switch (match.effect) {
        case 'stronger':    effectShort = '&#9650; '; break;
        case 'weaker':      effectShort = '&#9660; '; break;
        case 'equivalent':  effectShort = '&#8776; '; break;
      }

      var li = $('<li/>')
               .hover(function () { preview.children().hide(); descTable.show(); }
                     ,function () { })
               .append($('<b/>').html(effectShort + match.name));

      ul.append(li);

      li.click(function() {
        galoisPost
              ( '/play/rewriteInput'
              , { exprpath: JSON.stringify(exprPath)
                , taskpath: JSON.stringify(taskPath)
                , choice: ix
                }
              , function (res) {
                  ungrabExpression();
                  return galoisHandleNewInputResponse (info.goalInfos,info.inputContext.inputInfo)(res);
              }
              );
        cleanup();
      });
    });

//    ul.mouseleave(function() { ul.remove(); preview.remove(); });
    // XXX: Append to here
    $('body').append(ul)
             .append(preview);

    var where = rendered_e; /*(info.inputContext === null)
              ? rendered_e
              : info.inputContext.inputInfo.dom.parents('table:first'); */

    var menuOptions = { my: "left top", at: "right-5 top+5", of: where };
    ul.menu(menuOptions).position(menuOptions);
    preview.position({ my: "left top", at: "left bottom+15", of: ul });
  }
}


// For draggable constraint (temporary)
function goal_tbody_id(unused) { return 'document'; }



function galoisRenderPalette(els,realNames,here) {
  var dom     = $('<table/>').addClass('palette');
  var palette = $('<div/>').hide();
  var snapbtn = $('<div/>')
                .addClass('text_button')
                .text('Snapshot');
  var restorebtn = $('<div/>')
                .addClass('text_button')
                .text('Restore');
  var btn     = $('<div/>')
                .addClass('text_button')
                .text('Palette');
  dom.append( [ $('<tr/>').append($('<td/>').append(snapbtn))
              , $('<tr/>').append($('<td/>').append(restorebtn))
              , $('<tr/>').append($('<td/>').append(btn))
              , $('<tr/>').append($('<td/>').append(palette))
              ]);

  palette.append(galoisRenderNumericLiteralWidget());

  var info = { gId: null
             , varTys: []
              // When we have proper typed wildcards we should fill these in
             , qVarColors: []
             , holeInfo: []
             , collapse: false
             , toggleVars: null
             , clickDispatch: galoisExpressionClicked
             , realNames: realNames
             , here: here
             };

  jQuery.each(els, function(ix,e) {
    palette.append(renderTopExpr(info, e, true));
  });

  btn.click(function() { palette.slideToggle(); });

  snapbtn.click(function() {
    galoisPost('/play/saveSnapshot', {}, function (res) {
      console.log(res.snapshot);
      alert(res.snapshot);
    });
  });

  restorebtn.click(function() {
    var snap = prompt('Snapshot code');
    if (snap != null) { // null on cancel
      loadSnapshot(snap, realNames, here);
    }
  });

  return dom;
}



function galoisRenderTimeCounter() {
  var color = 'green';

  var me = $('<table/>')
           .css('display', 'inline-block')
           .css('border-collapse', 'collapse');
  var row1 = $('<tr/>');
  var row2 = $('<tr/>');
  me.append([row1,row2]);

  var curVal = 1;
  var display = $('<td/>')
                .attr('id','timeCounter')
                .css('color',color)
                .attr('rowspan','2')
                .text(curVal.toString());

  function button_click(ch) { return function () {
      var newVal = curVal + ch;
      if (newVal < 1 || newVal > 20) return;
      curVal = newVal;
      display.text(curVal.toString());
      return false;
    };
  }

  var goUp =
    $('<td/>')
    .css('color',color)
    .addClass('clickable')
    .html('&#x25b2;')
    .click(button_click(1));

  var goDown =
    $('<td/>')
    .html('&#x25bc;')
    .css('color',color)
    .addClass('clickable')
    .click(button_click(-1));

  var lab = $('<td/>').attr('rowspan','2').css('color',color).text('time:')

  row1.append(lab,display,goUp);
  row2.append(goDown);

  return me;
}





function galoisRenderNumericLiteralWidget() {
  var me = $('<table/>')
         .addClass('num-widget');
  var row1 = $('<tr/>');
  var row2 = $('<tr/>');
  me.append([row1,row2]);


  function onClick() {
    galoisPost
      ( '/play/grabExpr'
      , { expr: curVal.toString() }
      , handleGrabInputResponse(row1)
      );
  }


  var curVal = 0;
  var display = $('<td/>')
                .attr('rowspan','2')
                .addClass('flatexpr')
                .addClass('literal')
                .addClass('big-expr')
                .addClass('clickable')
                .text(curVal.toString())
                .click(function () {
                   if (click_modifier_state !== 'grab') return;
                   onClick();
                });

  function button_click(ch) { return function () {
      curVal += ch;
      display.text(curVal.toString());
      if (row1.hasClass('grabbed')) {
        onClick();
      }
      return false;
    };
  }

  var goUp =
    $('<td/>')
    .addClass('num-widget-button')
    .addClass('clickable')
    .html('&#x25b2;')
    .click(button_click(1));

  var goDown =
    $('<td/>')
    .html('&#x25bc;')
    .addClass('num-widget-button')
    .addClass('clickable')
    .click(button_click(-1));

  row1.append(display,goUp);
  row2.append(goDown);

  return me;
}


function kennyRPG(x) {
  return '/static/img/kenny_rpg/PNG/rpgTile' + x + '.png';
}




function grassArea(wi,hi,tiles) {

  function td() { return $('<td/>').css('padding','0').css('border', '0'); }

  function setBg(i,x) {
    return i.css('background-image', 'url("' + kennyRPG(x) + '")')
            .css('margin','0');
  }

  function corrner(x) {
    return setBg ( $('<div/>').css('width', '64px').css('height','64px'), x );
  }


  var content = $('<div/>')
                .addClass('input-test')
                .css('overflow', 'auto');

  if (wi !== null) content.css('width', wi)
  if (hi !== null) content.css('height', hi)

  var mid = setBg(td(), tiles.c)
            .append(content);

  var dom = $('<table/>')
            .css('border-collapse','collapse')
            .css('margin', '50px')
            .append( [ $('<tr/>').append (
                         [ td().append(corrner(tiles.nw))
                         , setBg (td(), tiles.n)
                         , td().append(corrner(tiles.ne))
                         ])

                     ,  $('<tr/>').append (
                         [ setBg (td(), tiles.w)
                         , mid
                         , setBg (td(), tiles.e)
                         ])

                     ,  $('<tr/>').append (
                         [ td().append(corrner(tiles.sw))
                         , setBg (td(), tiles.s)
                         , td().append(corrner(tiles.se))
                         ])
                    ]);

  return { dom: dom, mid: content };
}







/* The `varClassDB` strucutre keeps track of which hole parameters
mention a given variable.  Then, if we click on that variable, we
can affect all the relevant hole paramameters.
The structure maps variables to sets of classes.
Sets are implemented as the keys of an object (the values are irrlelevant).
For example, if variable 2 is mentioned in two parameters, identified
by `class1` and `class2`, then part of the strucutre would look like this:

  [2]['class1'] = null
  [2]['class2'] = null

*/
function addVarClassesFromHoleParams(expr, varClassDB) {
  var struct = expr.struct;

  if (struct.tag !== 'hole') return;

  var h = hole_name(struct.inputId, struct.inputType);

  jQuery.each(struct.params, function (ix, param) {
    var cl = paramClass(h, ix);
    jQuery.each(param.varIds, function (qix, qv) {
      varClassDB[qv.toString()][cl] = null;    // The `true` does not matter.
    });
  });
}

// Compute the full mapping from the qunatified variables in a goal
// to the relevant parameters in the schematic predicates.
function makeVarClassDB(g) {
  var db = {};
  jQuery.each(g.vars, function(ix,_) { db[ix] = {}; });
  addVarClassesFromHoleParams(g.conc.expr, db);
  jQuery.each(g.asmps, function(ix,expr) {
    addVarClassesFromHoleParams(expr.expr, db);
  });

  // Now we flatten the sets into a list.
  var new_db = {};
  jQuery.each(db, function(ix,set) {
            var db_list = [];
            jQuery.each(set, function(el,unused) { db_list.push(el); });
            new_db[ix] = db_list;
          });

  return new_db;
}


// A unique name to identify a hole.
// The `id` alone is not sufficient alone becaise pre-and-post conditions
// for a function come from the same input (i.e., have the same id),
// but there are really two schematic things that need to be filled in.
function hole_name(id,ty) {
  return 'hole_' + id.toString() + '_' + ty;
}

// This is used to identify a specific parameter to a hole,
// so that they can be shown or hidden.
function paramClass(hole_name, ix) {
  return 'hole_param' + hole_name + '_' + ix.toString();
}

/* Render a thing that acts as an on/off buttong.

   thing: is what we click on
   onlyOn: boolean flag, indicating if this should only turn on things (true),
           or toggle them (false).
   classes: a list of classes, indicating what's affected.  An element is
            affected if it has any of the classes.

*/
function renderToggler(thing,onlyOn,classes) {
  var permHidden;
  var tempVisible;
  var els;

  function getAffected() {
    var col = $([]);
    jQuery.each(classes, function(ix,c) { col = col.add('.' + c); });
    return col;
  }

  thing.mouseenter(function() {
          els = getAffected();

          permHidden  = els.filter('.param_invisible');
          tempVisible = permHidden;

          tempVisible.removeClass('param_invisible');
       })
       .mouseleave(function() {
          tempVisible.addClass('param_invisible');
       })
       .click(function() {

          if (click_modifier_state !== 'occurs' &&
              click_modifier_state !== null) {
            return true;
          }

          if (!onlyOn && permHidden.length == 0) {
            // Hide everyone
            els.addClass('param_invisible');
            permHidden = els;
          } else {
            // Show everyone
            permHidden = $([]);
            els.removeClass('param_invisible');
          }
          tempVisible = $([]);
          return false;
       });
}


function galoisRenderSuggestions(goalInfos, inputInfo) {
  inputInfo.asmp.buttonCell
                .append(galoisRenderSuggestionsInner(goalInfos,inputInfo));

  inputInfo.conc.buttonCell
                .append(galoisRenderSuggestionsInner(goalInfos,inputInfo));
}

// Render the alterate solutions button for a given input id,
function galoisRenderSuggestionsInner(goalInfos, inputInfo) {

  function updateHoleInput(value) {
        galoisPost
          ( '/play/sendInput'
          , { id: inputInfo.input.id, value: value }
          , galoisHandleNewInputResponse (goalInfos, inputInfo)
          );
  }

  var sugs = $('<div/>')
             .css('max-height', $(window).height * 3 / 4)
             .addClass('suggestions').hide();

  var btn = $('<div/>')
          .addClass('tab_button')
          .addClass('suggestions_btn')
          .addClass('not_clicked');

  sugs.click(function() {
    sugs.hide();
    btn.addClass('not_clicked').removeClass('clicked');
  });

  btn.click(function() {
    if (btn.hasClass('clicked')) {
      sugs.hide();
      btn.removeClass('clicked')
         .addClass('not_clicked');
    } else {
      $('.suggestions').hide();
      $('.suggestions_btn.clicked').removeClass('clicked')
                                   .addClass('not_clicked');
      btn.addClass('clicked');

  sugs.empty();

  var theInput = inputInfo.input;

  galoisPost( '/play/getSuggestionsForInput'
             , { input: theInput.id }
             , function (res) {
                 jQuery.each(res, function(ix,obj) {
                    var e = renderParamExpr( { params: theInput.params, def: obj.expr } )
                           .click(function () {
                              updateHoleInput(obj.expr_text);
                              sugs.hide();
                              btn.removeClass('clicked')
                                 .addClass('not_clicked');
                              return false; // handled, don't propagate
                            });

                    sugs.append(e).append($('<hr/>'));
                 });
               }
             );


      sugs.show();
    }
    return false;
  });

  return [sugs,btn];
}


function galoisAddCallSolutions(goalInfos, inputInfo, sel_sln) {

  var finp           = inputInfo.input;

  var selected = $([]);
  var protoButton = $('<div/>')
                    .addClass('function_choice_button')
                    .addClass('unselected');

  // Add entries for each existing solution.
  jQuery.each(finp.solutions, function(ix,sln) {

    // Setup the line between the pre-and post conditions.
    // Clicking on this selected the given pair.
    var btnAsmp = protoButton.clone();
    var btnConc = protoButton.clone();
    inputInfo.asmp.buttonCell.append(btnAsmp);
    inputInfo.conc.buttonCell.append(btnConc);

    if (ix === sel_sln) {
      btnAsmp.removeClass('unselected').addClass('selected');
      btnConc.removeClass('unselected').addClass('selected');
    }


    function clicked() {
      // avoid double selection
      if (selected.is(btnAsmp, btnConc)) return;

      galoisPost('/play/sendCallInput',
          { inputId: finp.id, slnId: sln.slnId },
          function(res) {
            if (res.error) { alert(res.error_message); return; }

            // Toggle the button graphic
            if (selected !== null) {
                selected.removeClass('selected').addClass('unselected');
            }
            selected = $([]).add(btnAsmp).add(btnConc);
            selected.removeClass('unselected').addClass('selected');

            invalidateGoals(goalInfos, res.invalidatedGoalIds);

            galoisFillInput(goalInfos, inputInfo, 'iPre', res.pres);
            galoisFillInput(goalInfos, inputInfo, 'iPost', res.posts);

            invalidateGoals(goalInfos, res.invalidatedGoalIds);
          });
    }



    btnAsmp.click(clicked);
    btnConc.click(clicked);
  });
}

function galoisAddNewPostHandlers(here, inputInfo) {
  inputInfo.asmp.newPost.click(function () {
    galoisPost( '/play/newPost'
              , { inputid: inputInfo.input.id }
              , function (res) {
                  if (res.error) { alert(res.error_message); return; }
                    renderTaskGroup3(inputInfo.input.function, 'post_'+res.result, here);
                });
  });
}

function markVisibility(task,path,visible) {
  if (path === "1" && // top level
      task.tag                === 'goal' &&
      task.goal.predicate.tag === 'assumption') {
        galoisPost
              ( '/play/setVisibility'
              , { taskpath: JSON.stringify(task)
                , visible: visible
                }
              );
  }
}

function markRevealed(task,path) { markVisibility(task,path, true ); }
function markHidden  (task,path) { markVisibility(task,path, false); }

sessionId = null;

function establishSessionId(callback) {

    var settings =
      { type: 'POST'
      , url: '/play/getSession'
      , data: {sessionid: ''}
      , dataType: 'json'
      , xhrFields: { withCredentials: true }
      , success: function(res) {
          sessionId = res.sessionid;
          return callback();
      }};

    jQuery.ajax(settings);

}

function galoisPost(url, params, callback) {

  if (sessionId == null) {
    establishSessionId(function() {
      galoisPost(url, params, callback);
    });
    return;
  }

  var params = jQuery.extend({}, params, { sessionid: sessionId });
  var settings =
    { success: callback
    , type: 'POST'
    , url: url
    , data: params
    , dataType: 'json'
    , xhrFields: { withCredentials: true }
    };

  jQuery.ajax(settings);
}
