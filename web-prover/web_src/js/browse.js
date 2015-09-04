
var paintings_array =
  { easy:           {url: "university-0",  width: 260, height: 388
                                        , left: 800, top: 100}
  , simple_loop:    {url: "lumbermill-0",  width: 352, height: 260
                                        , left: 820, top: 760 }
  , simple_loop_if: {url: "stonemason-0",  width: 434, height: 296
                                        , left: 200, top: 700}
  , loop_nested:    {url: "workshop-0",    width: 284, height: 360
                                         , left: 1500, top: 0}
  , call_easy:      {url: "marketplace-0", width: 466, height: 308
                                         , left: 1100, top: 350}
  , complex:        {url: "hatchery-0",    width: 464, height: 346
                                         , left: 1300, top: 650}
  , boss:           {url: "castle-0",      width: 484, height: 512
                                         , left: 200, top: 100}
  };

function getPainitng(x,w) {
  var img = paintings_array[x];

  var img_url = '/static/img/VA/paintings/' + img.url + '.png';
  var img_w   = w;
  if (img_w === null) img_w = img.width;

  var scale = w / img.width;
  var img_h = img.height * scale;

  return $('<img/>')
         .attr('title',x)
         .attr('src', img_url)
         .css('width', img_w + 'px')
         .css('height', img_h + 'px');
}


function rewardPic(img, num) {

  var rows = Math.floor (Math.sqrt(num));
  var cols = rows;
  var rest = num - rows * rows;
  rows += Math.floor(rest / cols);
  var extra = num - (rows * cols);
  if (extra >= 1) ++rows;

  var img_url = '/static/img/VA/paintings/' + img.url + '.png';
  var w = img.width; // 640;
  var unit_width = w / cols;
  // var w = unit_width * cols;
  var h = (w / img.width) * img.height;

  var me = $('<table/>')
           .css('width',             w + 'px')
           .css('height',            h + 'px')
           .css('position', 'fixed')
           .css('left', img.left)
           .css('top', img.top)
           .css('background-image',  'url(' + img_url + ')')
           .css('background-repeat', 'no-repeat')
           .css('background-size',   w + 'px ' + h + 'px');

  var cells = [];
  var r;
  var c
  for (r = 0; r < rows; ++r) {
    var row = $('<tr/>');
    for (c = 0; c < cols; ++c) {
      var cell = $('<td/>');
      cells[r * cols + c] = cell;
      if (r === rows - 1 && extra >= 1 && c >= extra) {
      } else {
        cell.addClass('not_done').addClass('piece_cell');
      }
      row.append(cell);
    }
    me.append(row);
  }

  return [me, cells];
}


function renderTaskGroup3(fun, grpName, here) {
  getMetaData (renderTaskGroup3_meta(fun,grpName,here));
}

function renderTaskGroup3_meta (fun, grpName, here) {
  return function (meta, realNames, cg) {
    var tasks = getTasksForGroup(meta, fun, grpName);

    var goBack = $('<div/>')
                 .css('position', 'fixed')
                 .css('bottom', '1em')
                 .css('right', '1em')
                 .text('back')
                 .addClass('clickable')
                 .addClass('text_button')
                 .addClass('back_button')
                 .click(function () { browseFunctions(here,fun,null); });


    here.fadeOut('slow', function() {
      here.empty();
      here.css('background-image', 'url("/static/img/VA/WorldMap_bkgd.jpg")')
           .css('background-repeat', 'no-repeat');

      var real = realNames[fun];
      if (real === undefined) real = '?'

      here.append($('<div/>').text(fun + ' / ' + real)
                  .css('text-align', 'center')
                  .css('font-weight', 'bold')
                  .css('font-family', 'monospace')
                  .css('color', 'orange')
                  .css('background-color', 'black'))


      here.append(goBack);

      jQuery.each(tasks, function(area,tasks) {
        renderArea(here, area, tasks, realNames);
      });

      here.append($('<div/>')
                  .text('all in one')
                  .css('position', 'fixed')
                  .css('bottom', '1em')
                  .css('right', '7em')
                  .addClass('text_button')
                  .addClass('clickable')
                  .click(function() {
                      startTask( { function: fun
                                 , group: grpName
                                 , name: 'massive'
                                 }
                                , realNames, here);
                   }));

      addCopyrights(here);
      here.fadeIn('slow');
    });
  }
}



function renderArea(here, area, tasks, realNames) {

  // Make painting, and sub-pieces.

  var pics   = rewardPic(paintings_array[area], tasks.length);
  var pic    = pics[0];
  var pieces = pics[1];

  jQuery.each(tasks, function(ix, taskPair) {
         var cell = pieces[ix];

         cell.addClass('clickable')
             .append($('<div/>').text(taskPair.taskName.name)
                     .css('background-color', 'rgba(0,0,0,0.8)')
                     .css('box-shadow', '0px 0px 5px 5px rgba(0,0,0,0.5)')
                     .css('display', 'inline-block')
                    )
             .click(function() { startTask(taskPair.taskName, realNames, here); })

         switch (taskPair.taskStatus) {
           case 'solved':
             cell.removeClass('not_done').addClass('done');
             break;
           case 'unsolved':
             break;
           case 'bad':
             cell.addClass('bad');
             break;
           case 'locked':
             cell.addClass('locked');
             break;
         }
      });

  here.append(pic);
}



