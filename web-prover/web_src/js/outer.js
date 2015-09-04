function browseFunctions(here,from) {

  getMetaData(function(meta,realNames,cg) {
  getCustomLinks(function(links) {
  getTagGroups(function(tagGroups) {

    var db = getGroupsMeta(meta);
    var stages = [];

    here.fadeOut('slow', function() {
      here.empty();
      here.css('background-image', 'url("/static/img/VA/WorldMap_bkgd.jpg")');

      here.append(customLinks(links,realNames,here));
      here.append(randomTasks(meta,realNames,here));
      here.append(randomTasksTagGroups(tagGroups,realNames,here));

      jQuery.each(db, function(f,finfo) {
        var me = $('<div/>')
                 .attr('id', f)
                 .css('display', 'inline-block')
                 .css('margin', '1em')
                 .css('padding','5px')
                 .css('background-color', '#999')
                 .css('box-shadow','0px 0px 10px 4px #ccf')

       me.text( getRealName(realNames, f) );


        jQuery.each(finfo, function(g,ginfo) {
           var gDiv = $('<div/>')
                      .css('background-color', 'rgba(0,0,0,0.2)')
                      .css('border', '1px solid black')
                      .css('margin', '5px');

           var btn = $('<div/>')
                     .text(g)
                     .css('cursor', 'pointer')
                     .css('text-align', 'center')
                     .css('padding', '2px')
                     .css('border-bottom', '1px solid black')
                     .click(function () {
                        renderTaskGroup3_meta(f,g,here)(meta,realNames);
                      });

            gDiv.append (btn);

            jQuery.each(ginfo.areaSet, function(area,present) {
              gDiv.append(getPainitng(area,24));
            });

            var allSolved = true;
            jQuery.each(ginfo.qs, function(q,number) {
              if (q !== 'solved') allSolved = false;
              gDiv.append($('<div/>').text(q + ': ' + number));
            });

            btn.css('background-color', allSolved ? '#393' : 'orange');

            me.append(gDiv);


        });

        var finfo = cg[f];
        if (finfo === undefined) {
          console.log(f + ' ' + getRealName(realNames, f) + ' was not in the callgraph');
        }
        if (stages[finfo.stage] === undefined)
          stages[finfo.stage] = $('<div/>')
                                .css('margin', '1em')
                                .css('background-color', 'rgba(51,0,51,0.5)')
                                .append($('<h2/>')
                                        .css('width', '2em')
                                        .css('text-align', 'center')
                                        .css('background-color', '#414')
                                        .css('color', '#f9f')
                                        .css('padding', '2px')
                                        .text(finfo.stage));
        stages[finfo.stage].append(me);
      });

      jQuery.each(stages, function(ix,stageDiv) {
        if (stageDiv === undefined) return true;
        here.append(stageDiv);
      });

      jQuery.each(cg, function(fun,finfo) {
        var popup = $('<div/>')
                    .css('border', '1px solid black')
                    .css('background-color', 'white')
                    .css('padding', '5px')
                    .css('position', 'absolute')
                    .hide();


        var note  = $([]);
        var callNames   = $('<ul/>');
        var callerNames = $('<ul/>');

        popup.append($('<h4/>').text('Calls:'))
             .append(callNames)
             .append($('<h4/>').text('Called by:'))
             .append(callerNames)


        jQuery.each(finfo.calls, function(ix,f) {
            note = note.add('#' + f);
            callNames.append($('<li/>').text(getRealName(realNames,f)));
        });

        var isTerminal = true;
        jQuery.each(finfo.calledBy, function(ix,f) {
            note = note.add('#' + f);
            callerNames.append($('<li/>').text(getRealName(realNames,f)));
            isTerminal = false;


        });

        var it = $('#' + fun);

        if (isTerminal) {
              it.append($('<img/>')
                    .attr('src','/static/img/PlanetCute_PNG/Tree_Short.png')
                    .css('width','32')
                    .css('height','48'));
            }


        it.append(popup)
          .hover( function () { note.addClass('out_calls');
                                popup.show();
                              }
                , function () { note.removeClass('out_calls'); popup.hide(); });
      });

      addCopyrights(here);
      here.fadeIn();
    });
  });
  });
  });
}



function randomTasksTagGroups(tagGroups,realNames,here) {

  var me = $('<div/>')
           .css('text-align', 'center');

  jQuery.each(tagGroups, function(area,todo) {
    me.append (
      $('<div/>')
              .css('display', 'inline-block')
              .css('margin', '1em')
              .css('padding','5px')
              .css('background-color', 'rgba(255,255,255,0.5)')
              .css('color', 'black')
              .css('text-align','center')
              .css('box-shadow','0px 0px 10px 4px #ffc')
              .append ( $('<div/>').text('Random task from'))
              .append (
                  $('<div/>').text(area)
                  .addClass('clickable')
                  .click(function () {
                     var taskId = Math.floor(Math.random() * todo.length);
                     console.log(todo[taskId])
                     startTask(todo[taskId], realNames, here);
                  })
               )
              .append($('<div/>').text('Available: ' + todo.length))
    );
  });
  return me;
}




function randomTasks(meta,realNames,here) {

  var db = getTasksByArea(meta);
  var me = $('<div/>')
           .css('text-align', 'center');

  jQuery.each(db, function(area,tasks) {
    var unsolved = tasks.filter(function(t) {
                              return t.taskStatus === 'unsolved'; });
    if (unsolved.length === 0) return true;
    me.append (
      $('<div/>')
              .css('display', 'inline-block')
              .css('margin', '1em')
              .css('padding','5px')
              .css('background-color', 'rgba(255,255,255,0.5)')
              .css('color', 'black')
              .css('text-align','center')
              .css('box-shadow','0px 0px 10px 4px #ffc')
              .append ( $('<div/>').text('Random task from'))
              .append (
                  getPainitng(area,64)
                  .addClass('clickable')
                  .click(function () {
                     var taskId = Math.floor(Math.random() * unsolved.length);
                     startTask(unsolved[taskId].taskName, realNames, here);
                  })
               )
              .append($('<div/>').text('Available: ' + unsolved.length))
    );
  });
  return me;
}


function customLinks(links, realNames, here) {
  var me = $('<div/>')
           .css('background-color', 'rgba(255,255,255,0.5)')
           .text('Bookmarks');

  jQuery.each(links, function(ix,link) {
    var div = $('<div/>')
              .text(link.name)
              .css('display','inline-block')
              .addClass('clickable')
              .css('color','#999')
              .css('background-color','rgba(0,0,0,0.5)')
              .css('padding','5px')
              .css('margin', '5px')
              .click(function() { startTask(link.task, realNames, here); });
    me.append(div);
  });

  return me;
}





