

var img_array =
  [ "creatures/big_eyes_creature"
  , "creatures/black_creature"
  , "creatures/black_power_creature"
  , "creatures/black_spikes_creature"
  , "creatures/blue_creature"
  , "creatures/blue_toy"
  , "creatures/brown_creature"
  , "creatures/cheeks_creature"
  , "creatures/china_creature"
  , "creatures/domokun_creature"
  , "creatures/dragon_creature"
  , "creatures/ears_creature"
  , "creatures/fire_creature"
  , "creatures/fire_toy"
  , "creatures/fiveeyes_creature"
  , "creatures/glasses_creature"
  , "creatures/green_creature"
  , "creatures/green_red_eyes_creature"
  , "creatures/green_toy"
  , "creatures/lady_yellow_creature"
  , "creatures/lilastoy"
  , "creatures/mask_toy"
  , "creatures/ninja_toy"
  , "creatures/nose_creature"
  , "creatures/orange_creature"
  , "creatures/orange_toy"
  , "creatures/pink_creature"
  , "creatures/pink_toy"
  , "creatures/pirate_creature"
  , "creatures/red_creature"
  , "creatures/red_eyes_creature"
  , "creatures/red_toy"
  , "creatures/scar_creature"
  , "creatures/six_hands_creature"
  , "creatures/smile_creature"
  , "creatures/swamp_creature"
  , "creatures/tentacles_creature"
  , "creatures/tie_creature"
  , "creatures/tooth_toy"
  , "creatures/white_creature"
  , "creatures/yellow_toy"

  , "VA/monsters/01"
  , "VA/monsters/02"
  , "VA/monsters/03"
  , "VA/monsters/04"
  , "VA/monsters/05"
  , "VA/monsters/06"
  , "VA/monsters/07"
  , "VA/monsters/08"
  , "VA/monsters/09"

  , "VA/monsters/11"
  , "VA/monsters/12"
  , "VA/monsters/13"
  , "VA/monsters/14"
  , "VA/monsters/15"
  , "VA/monsters/16"
  , "VA/monsters/17"
  , "VA/monsters/18"
  , "VA/monsters/19"

  , "VA/monsters/21"
  , "VA/monsters/22"
  , "VA/monsters/23"
  , "VA/monsters/24"
  , "VA/monsters/25"
  , "VA/monsters/26"
  , "VA/monsters/27"
  , "VA/monsters/28"
  , "VA/monsters/29"

  , "VA/monsters/31"
  , "VA/monsters/32"
  , "VA/monsters/33"
  , "VA/monsters/34"
  , "VA/monsters/35"
  , "VA/monsters/36"
  , "VA/monsters/37"
  , "VA/monsters/38"
  , "VA/monsters/39"

  , "VA/monsters/41"
  , "VA/monsters/42"
  , "VA/monsters/43"
  , "VA/monsters/44"
  , "VA/monsters/45"
  , "VA/monsters/46"
  , "VA/monsters/47"
  , "VA/monsters/48"
  , "VA/monsters/49"

  , "VA/monsters/50"


  ];


function renderParamExpr(holeDef) {
  var ps = holeDef.params;
  var e  = holeDef.def;
  var colors = [];
  var varTys = [];

  jQuery.each(ps, function(ix,p) {
    colors[ix] = null;
    varTys[ix] = p;
  });

  var info = { gId: null
             , varTys: varTys
             , qVarColors: colors
             , holeInfo: []
             , collapse: false
             , toggleVars: null
             , taskPath: null
             , clickDispatch: function () {}
             };

  return renderExpr(info, e, false);
}





function drawTy(ty, color, lab) {
  var style = color === null
            ? { fill: '#fff'
              , strokeWidth: 1
              , stroke: '#000'
              , 'stroke-dasharray': '5,2'
              }
            : { fill: color
              , strokeWidth: 1
              , stroke: '#000'
              };

  var topStyle = { fill: '#000', strokeWidth: 0 };
  var svg;

  switch (ty) {
  case 'int':
    svg   = Snap(30,30);
    svg.rect(0,0,30,30).attr(style);
    if (lab !== null)
      svg.text(8, 18, lab).attr({ 'font-size': 10 });
    break;

  case 'addr':
    svg   = Snap(30,30);
    svg.path('M0,29H30L15,0Z').attr(style);
    if (lab !== null)
      svg.text(8, 26, lab).attr({ 'font-size': 10 });
    break;

  default:
    svg   = Snap(30,42);
    if (ty === 'map int int' || ty === 'map addr int') {
      svg.rect(0,12,30,30).attr(style);

      if (lab !== null)
        svg.text(8, 30, lab).attr({ 'font-size': 10 });
    }

    if (ty === 'map addr addr') {
      svg.path("M0,41H30L15,12Z").attr(style);

      if (lab !== null)
        svg.text(8, 38, lab).attr({ 'font-size': 10 });
    }

    if (ty === 'map int int')
      svg.rect(5,0,20,9).attr(topStyle);

    if (ty === 'map addr int' || ty === 'map addr addr')
      svg.path("M5,10H25L15,0Z").attr(topStyle);

    break;
  }

  return $('<div/>').append($(svg.node)).addClass('flatexpr');
}

function renderPrePost(pre, post) {
    var preCell = $('<td/>');
    var sepCell = $('<td/>');
    var postCell = $('<td/>');
    var table = $('<table/>').append($('<tr/>').append([preCell,sepCell,postCell]));

    preCell.addClass('iPre').append(pre);
    sepCell.addClass('iPre_iPost_sep').html('&#8866;');
    postCell.addClass('iPost').append(post);

    return table;
}

function renderTopExpr(info, e, draggable) {
  return renderExpr ( jQuery.extend({}, info, { taskPath: e.taskPath })
                    , e.expr
                    , draggable
                    );
}

function renderVar(varId) {
  var icon_num = img_array.length;
  if (0 <= varId && varId < icon_num) {
    return $('<div/>')
           .addClass('small-var-icon')
           .css('width','16px')
           .css('height','16px')
           .css( 'background-image'
               , 'url("/static/img/' + img_array[varId] + '_16x16.png")');

  } else if (icon_num <= varId && varId < icon_num + 100) {

          var iconId = varId - icon_num;

          var varX = - (16 * (iconId % 10) + 10);
          var varY = - (16 * Math.floor(iconId / 10) + 10);

          return $('<div/>')
                 .addClass("small-qvar")
                 .css('background-position'
                     , varX.toString() + 'px ' + varY.toString() + 'px');
  } else {
    return $('<div/>')
           .addClass('small-var')
           .text('v' + varId);
  }
}


function renderExpr(info, e, draggable, msg) {

    var myTaskPath = info.taskPath;

    var meSmall = $('<div/>')
                .addClass('small-expr');
    var meBig   = doRenderExpr(e)
                .addClass('big-expr');

    var me = $('<div/>')
           .css('display', 'inline-block')
           .append(meBig)
           .append(meSmall);


    jQuery.each(e.varIds, function(ix,varId) {
      meSmall.append( renderVar(varId) );
    });

    function normalMeSmallClickHandler(meBig) {
      return function() {
        meSmall.hide();
        meBig.show();
        setTimeout(jsPlumb.repaintEverything, 0);
        return false
      }
    }

    var ty = e.struct.tag;

    if (ty === 'dvar') {
      meSmall.one("click", function() {

          galoisPost
             ( "/play/getExpression"
             , { taskpath: JSON.stringify(myTaskPath)
               , exprpath: JSON.stringify(e.path)
               }
             , function(res) {
                 if (res.result !== null) {
                   var newExpr = renderExpr(info, res.result, false);
                   newExpr.children('.small-expr').hide();
                   newExpr.children('.big-expr').show();
                   var myClasses = me.attr('class');
                   newExpr.addClass(myClasses);
                   me.replaceWith(newExpr);//append(newExpr.children());
                 }
             });
         return false;
      });
    } else {
      meSmall.click(normalMeSmallClickHandler(meBig));
    }

    // Special case for dvar is due to the overloading of
    // collapse being used for dvar expansion.
    if ((!info.collapse && ty !== 'dvar') ||
          ty === 'pvar' ||
          ty === 'hole' ||
          ty === 'lit'  ||
          ty === 'qvar' ||
          (ty === 'app' && e.struct.params.length === 0) ||
          (ty === 'app' && e.struct.fun === '&#8788;')
        ) {
      meSmall.hide();
    } else {
      meBig.hide();
    }

    meBig
      .addClass('clickable')
      .click(function () {
          if (click_modifier_state === 'hide' ||
              click_modifier_state === null
                && myTaskPath      !== null
                && myTaskPath.tag  === 'goal'
                && ty !== 'qvar'
                && ty !== 'dvar'
                && ty !== 'lit'
             ) {
            meBig.hide();
            meSmall.show();
            setTimeout(jsPlumb.repaintEverything, 0);

            return false
          } else {
            return info.clickDispatch(info, e, me, click_modifier_state)
          }

      });

    if (draggable !== true) return me;

    var containment = info.gId === null
                    ? "document"
                    : '#' + goal_tbody_id(info.gId);

    return me.draggable (
      { revert: 'invalid'
      , helper: 'clone'
      , zIndex: 100
      , appendTo: "body"
      , delay: 200
      , containment: containment
      , start: function(ev,ui) { ui.helper.data('storm-drag', { task: myTaskPath, expr: e.path }); }
      }
    );


  function renderTuple(params) {

    var me  = $('<table/>').addClass('expr');
    var row = $('<tr/>');

    me.append(row);

    jQuery.each(params, function(ix,p) {
      var cell = $('<td/>').append(renderExpr(info,p,false));
      if (ix > 0) { cell.addClass('app_arg'); }
      row.append ( cell );
    });


    return me;
  }

  function renderApp(fun,params) {

    var me   = $('<table/>').addClass('expr');
    var row1 = $('<tr/>');
    var row2 = $('<tr/>');

    me.append(row1);
    me.append(row2);

    row1.append( $('<td/>')
                  .attr('colspan', params.length)
                  .addClass('app_heading')
                  .html(fun)
               );

    jQuery.each(params, function(ix,p) {
      var cell = $('<td/>').append(renderExpr(info,p,false));
      if (ix > 0) { cell.addClass('app_arg'); }
      row2.append ( cell );
    });


    return me;
  }




  // Custom rendering for things like `is_uint32`.
  function renderTypePred(sign, sz, expr) {
    return renderApp(sign + sz, [expr]);
  }

  // Custom rendering for things like `to_uint32`.
  function renderTypeCast(sign, sz, expr) {

    var lo = '';
    var hi = '';

    switch(sign) {
    case 'S':
      lo = '-2<sup><small>' + (sz-1) + '</small></sup>'
      hi =  '2<sup><small>' + (sz-1) + '</small></sup>'
      break;
    case 'U':
      lo = '0'
      hi = '2<sup><small>' + sz + '</small></sup>'
      break;
    }

    var label = '[&nbsp;' + lo + '&nbsp;,&nbsp;' + hi + '&nbsp;)';

    return renderApp(label, [expr]);
  }

  function drawDigit(n) {
    var offX = [25, 110, 200, 280, 360];

    var me = $('<div/>')
             .css('background-image', 'url("/static/img/numbers.jpg")')
             .css('display', 'inline-block')
             .css('width',  '12px')
             .css('height', '19px')
             .css('background-size', '80px');

    var varX = - Math.floor(offX[n%5] * 80 / 450);
    var varY = - (Math.floor(n/5) * 25 + 3)
    me.css('background-position',
                  varX.toString() + 'px ' + varY.toString() + 'px');

    return me;
  }

  function drawNum(n) {
    var me = $('<div/>')
             .css('box-shadow', '0px 0px 1px 1px rgba(0,0,0,0.8)')
             .css('display', 'inline-block')
             .css('white-space', 'nowrap');
    var haveDigs = false;
    while (n >= 10) {
      haveDigs = true;
      me.prepend(drawDigit(n % 10));
      n = Math.floor(n / 10);
    }

    if (n !== 0 || !haveDigs)
      me.prepend(drawDigit(n));

    return me;
  }


  function drawVar(color, ty, varName, varId) {

      var me;

      var icon_num = img_array.length;

      if (color !== null && 0 <= varId && varId < icon_num) {

        me = $('<div/>').addClass('flatexpr')
                        .addClass('qvar_icon')
                        .css('width', '32px')
                        .css('height', '32px')
                        .css('background-image', 'url("/static/img/' + img_array[varId] + '_32x32.png")');

      } else if (color !== null && icon_num <= varId && varId < icon_num + 100) {

          var iconId = varId - icon_num;

          me = $('<div/>').addClass("qvar").addClass("flatexpr");
          var varX = - (30 * (iconId % 10) + 18);
          var varY = - (30 * Math.floor(iconId / 10) + 18);

          me.css('background-position', varX.toString() + 'px ' + varY.toString() + 'px');

      } else {

          me = drawTy(ty, color, varName);

      }

      if (info.toggleVars !== null) {
        renderToggler(me, true, info.toggleVars[varId]);
      }

      // Special case for variables in "templates"
      if (color === null) {
        me = $('<div>')
          .addClass('paramdef')
          .append(me);
      }

      return me.attr('title', varName);

  }


  function doRenderExpr(e) {
    var expr = e.struct;

    if (expr.tag == 'qvar') {
      return drawVar( info.qVarColors[expr.varId]
                    , info.varTys[expr.varId].text
                    , varName(info.gId, expr.varId)
                    , expr.varId);

    }

    if (expr.tag == 'lit') {
      var str;
      switch(expr.text) {
        case 'true':  str = '&#10201;'; break;
        case 'false': str = '&#10200;'; break;
        default:      str = expr.text;
      }

      var reps = [str];
      var curRep = 0;
      jQuery.each(expr.alternate, function(ix,alt) {
        reps.push(alt);
      });
      if (reps.length > 1) curRep = 1;

      var div = $('<div/>')
              .html(reps[curRep])
              .addClass('flatexpr')
              .addClass('literal');

      div.click(function () {
        if (click_modifier_state !== null) return;
        curRep = (1 + curRep) % reps.length;
        div.html(reps[curRep]);
        return false;
      });
      return div;
    }


    if (expr.tag == 'pvar') {
      // We discard the taskPath at this point because you can not click
      // inside parameter definition boxes. The click handlers know to
      // cascade these clicks to the outer container.
      var nowhereInfo = jQuery.extend({}, info, {taskPath: null});
      // var pclass = paramClass(info.holeName,expr.param);

      var me = $('<div/>')
             .addClass('paramdef')
             .append(renderExpr(nowhereInfo, expr.defn, false));

      if (info.inputContext !== undefined) {
        var input = info.inputContext.inputInfo.input;
        var hname = hole_name(input.id, info.inputContext.inputType);
        var pclass = paramClass(hname,expr.param);
        me.addClass(pclass);
        if ($('.'+ pclass +'.param_invisible').size() != 0) {
          me.addClass('param_invisible');
        }
      }


      return me;
    }

    if (expr.tag == 'app') {

      switch (expr.fun) {
        case 'Mk_addr':   return renderTuple(expr.params);
        case 'Mk_addrmap':return renderTuple(expr.params);
        case 'is_uint8':  return renderTypePred('U', '8', expr.params[0]);
        case 'is_uint16': return renderTypePred('U', '16', expr.params[0]);
        case 'is_uint32': return renderTypePred('U', '32', expr.params[0]);
        case 'is_uint64': return renderTypePred('U', '64', expr.params[0]);
        case 'is_sint8':  return renderTypePred('S', '8', expr.params[0]);
        case 'is_sint16': return renderTypePred('S', '16', expr.params[0]);
        case 'is_sint32': return renderTypePred('S', '32', expr.params[0]);
        case 'is_sint64': return renderTypePred('S', '64', expr.params[0]);
        case 'to_uint8':  return renderTypeCast('U', 8, expr.params[0]);
        case 'to_uint16': return renderTypeCast('U', 16, expr.params[0]);
        case 'to_uint32': return renderTypeCast('U', 32, expr.params[0]);
        case 'to_uint64': return renderTypeCast('U', 64, expr.params[0]);
        case 'to_sint8':  return renderTypeCast('S', 8, expr.params[0]);
        case 'to_sint16': return renderTypeCast('S', 16, expr.params[0]);
        case 'to_sint32': return renderTypeCast('S', 32, expr.params[0]);
        case 'to_sint64': return renderTypeCast('S', 64, expr.params[0]);
        case '[<-]':      return renderArrUpd(expr.params[0], expr.params[1], expr.params[2]);
        case '[]':        return renderArrSel(expr.params[0], expr.params[1]);
        case 'shift':     return renderInfix('&#x27a1;', expr.params[0], expr.params[1]);
        case 'mod':       return renderInfix('<i>mod</i>', expr.params[0], expr.params[1]);
        case 'div':       return renderInfix('<i>div</i>', expr.params[0], expr.params[1]);
        case "__'wildcard'__": return $('<div/>')
                                      .text('?')
                                      .addClass('flatexpr')
                                      .addClass('literal');

        case 'valid_rw': return renderValid1('RW', expr.params[0], expr.params[1], expr.params[2]);
        case 'valid_rd': return renderValid1('RD', expr.params[0], expr.params[1], expr.params[2]);
        case '-': return renderInfix('&#8722;',  expr.params[0], expr.params[1]);
        case 'negate': return renderNegate(expr.params[0]);
        case '/\\':
        case '&&': return renderAnd(e);

        case '\\/':
        case '||': return renderInfix('&#8744;', expr.params[0], expr.params[1]); // ∨
        case '+' : return renderInfix('+', expr.params[0], expr.params[1]);
        case '*' : return renderInfix('&#215;',  expr.params[0], expr.params[1]); // ×
        case '<=': return renderInfix('&#8804;', expr.params[0], expr.params[1]); // ≤
        case '<>': return renderInfix('&#8800;', expr.params[0], expr.params[1]); // ≠
        case '->': return renderInfix('&#10230;', expr.params[0], expr.params[1]); // ⟶
        case '<':  return renderInfix('&lt;', expr.params[0], expr.params[1]);
        case '>':  return renderInfix('&gt;', expr.params[0], expr.params[1]);
        case '=':  return renderInfix('=', expr.params[0], expr.params[1]);

        default: return renderApp( expr.fun.toUpperCase(), expr.params );
      }
    }

    if (expr.tag === 'error') return renderError ( expr.message, expr.expr )
    if (expr.tag === 'note') return renderNote ( expr.message, expr.expr )

    return $('<div/>')
           .addClass('expr')
           .append('??? ' + expr.tag);
  }

  function rightArrow() {
    return $('<table/>')
           .addClass('right-arrow')
           .append($('<tr/>')
                  .append($('<td/>')
                          .addClass('right-arrow-body')
                          .append($('<hr/>')))
                  .append($('<td/>')
                          .addClass('right-arrow-head')
                          .html("&#9654;"))
                  );
  }

  function renderNote(msg,e) {

     if (e.struct.tag == "app" && e.struct.fun == "__'wildcard'__") {
       var me   = $('<table/>')
       var row1 = $('<tr/>')
       var row2 = $('<tr/>')

       me.append(row1)
       me.append(row2);

       row1.append( $('<td/>')
                    .text(msg)
                    .css('font-weight', 'bold')
                    .css('font-family', 'monospace')
                    .css('text-align', 'center')
                  )
       row2.append ( $('<td/>')
                        .css('text-align', 'center')
                        .append(renderExpr(info,e,false))
                   )

       return me
     } else {
       return renderExpr(info,e,draggable)
     }
  }

  function renderError(msg,e) {

    var me   = $('<table/>')
               .addClass('expr')
    var row1 = $('<tr/>')
    var row2 = $('<tr/>')

    me.append(row1)
    me.append(row2);

    var fg = '#f96'
    var bg = 'rgba(0,0,0,0.5)'

    row1.append( $('<td/>')
                 .text('!')
                 .attr('rowspan','2')
                 .css('background-color', bg)
                 .css('color', 'red')
                 .css('font-size', '40px')
                 .css('font-weight', 'bold')
               )

    row1.append( $('<td/>')
                 .text(msg)
                 .css('background-color', bg)
                 .css('color', fg)
                 .css('font-weight', 'bold')
                 .css('font-family', 'monospace')
               )
    row2.append ( $('<td/>')
                  .append(renderExpr(info,e,false))
                  .css('background-color', 'rgba(255,255,255,0.5)')
                )

    return me
  }

  // Render valid
  function renderValid1(valTy, heapE, addrE, sizeE) {
    var me = $('<table/>').addClass('expr');
    var row1 = $('<tr/>');
    var row2 = $('<tr/>');
    var row3 = $('<tr/>');

    row1.append( $('<td/>')
                 .attr('colspan', 2)
                 .addClass('valid_header')
                 .text('VALID ' + valTy)
               );

    row2.append( $('<td/>')
                 .addClass('valid_addr')
                 .append(renderExpr(info, addrE, false)) )
        .append( $('<td/>')
                 .addClass('valid_size')
                 .append(renderExpr(info, sizeE, false)) );

    row3.append( $('<td/>')
                 .attr('colspan', '2')
                 .addClass('valid_heap')
                 .append(renderExpr(info, heapE, false))
               );

    return me.append([row1, row2, row3]);
  }

  // Render negations
  function renderNegate(expr) {
      return renderApp('NEGATE', [expr]);
  }

  function renderInfix(op, left, right) {

      var me = $('<table/>').addClass('expr');
      var row = $('<tr/>');
      me.append(row);

      var lab = $('<span/>').html(' ' + op + ' ');
      row.append( $('<td/>').append( renderExpr(info,left,false) ) )
         .append( $('<td/>').append( lab ) )
         .append( $('<td/>').append( renderExpr(info,right,false) ) );

      return me
  }

  // Render grouped valid (XXX: obsolete?)
  function renderValid(isRW, heap, object, offset, size) {
    var me      = $('<table/>');
    var eHeap   = renderExpr(info, heap, false);
    var eObject = renderExpr(info, object, false);
    var eOffset = renderExpr(info, offset, false);
    var eSize   = renderExpr(info, size, false);

    var row1 = $('<tr/>')
               .append ($('<th/>').text('valid'))
               .append ($('<th/>').text('offset'))
               .append ($('<th/>').text('size'));
    var row2 = $('<tr/>')
               .append ($('<th/>')
                        .attr('rowspan','3')
                        .append($('<span/>')
                                .text(isRW ? 'rw' : 'rd'))
                       )
               .append ($('<td/>').append(eOffset))
               .append ($('<td/>').append(eSize));
    var row3 = $('<tr/>')
               .append($('<td/>').attr('colspan', '2').append(eObject));
    var row4 = $('<tr/>')
               .append($('<td/>').attr('colspan', '2').append(eHeap));

    return me.addClass('valid')
             .append(row1)
             .append(row2)
             .append(row3)
             .append(row4);
  }

  // Custom code for rendering conjucntions
  function renderAnd(expr) {

    var conjs = $('<div/>').addClass('conj');
    var queue = [expr];

    while (0 < queue.length) {
      var current = queue.pop();
      var struct  = current.struct;
      if (struct.tag === 'app' && (struct.fun === '/\\' || struct.fun === '&&')) {
        queue.push(struct.params[1]);
        queue.push(struct.params[0]);
      } else {
        conjs.append(renderExpr(info, current, draggable).addClass('pred'));
      }
    }

    return conjs;
  }

  function renderArrSel(arr, ix) {

    var indexRow   = $('<tr/>');
    var indexTable = $('<table/>').append(indexRow);

    var lbrack = $('<td/>').addClass('lbracket').html('&nbsp;');
    var rbrack = $('<td/>').addClass('rbracket').html('&nbsp;');
    var ixcell = $('<td/>').append(renderExpr(info, ix, false));
    indexRow.append([lbrack, ixcell, rbrack]);

    return $('<table/>')
             .addClass('select_expr')
             .addClass('expr')
             .append($('<tr/>')
                     .append($('<td/>')
                              .append(renderExpr(info, arr, false)) )
                     .append($('<td/>')
                              .append(indexTable)));

  }

  function renderArrUpd(arr, ix, val) {

    var indexRow   = $('<tr/>');
    var indexTable = $('<table/>').append(indexRow);

    var lbrack = $('<td/>').addClass('lbracket').html('&nbsp;');
    var rbrack = $('<td/>').addClass('rbracket').html('&nbsp;');
    var ixcell = $('<td/>').append(renderExpr(info, ix, false));
    var assign = $('<td/>').html('&#8788;');
    var valcell = $('<td/>').append(renderExpr(info, val, false));
    indexRow.append([lbrack, ixcell, rbrack]);

    return $('<table/>')
             .addClass('select_expr')
             .addClass('expr')
             .append($('<tr/>')
                     .append($('<td/>').append(renderExpr(info, arr, false)) )
                     .append($('<td/>').append(indexTable))
                     .append(assign)
                     .append(valcell));

  }

  /* Pick a name for a given variable.
  The `goalId` may be null, if we are picking variables outside a goal
  (e.g., in a template) */
  function varName(goalId, varIx) {
    var d = Math.floor(varIx / 26);
    var r = varIx % 26;
    var gPref = goalId === null ? '' : ('g' + goalId.toString());
    return gPref + String.fromCharCode('a'.charCodeAt(0) + r) +
           (d === 0 ? '' : d.toString());
  }


}




