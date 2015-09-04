// The default behavior of getJSON appears to return outdated
// pages, this forces them to load.
function actuallyGetJSON(url, k) {
  return jQuery.ajax({
     dataType: 'json',
     url: url,
     data: {},
     success: k,
     cache: false // <-- deviation from getJSON defaults
  });
}

function getRealNames(k) {
  return actuallyGetJSON('/static/realnames.json', k)
          .fail(function() { 'failed to get realnames' });
}


function getCustomLinks(k) {
  return actuallyGetJSON('/static/custom_links.json', k)
         .fail(function(a) { console.log('failed to get links');
                             console.log(a);
                            k([]); });
}

function getTagGroups(k) {
  return actuallyGetJSON('/static/tag-groups.json', k)
         .fail(function(a) { console.log('failed to get tag-groups')
                             console.log(a)
                             k({})
                           })
}

function getMetaData(k) {
  actuallyGetJSON('/static/metadata.json',
  function(meta) {
    getRealNames(function(reals) {
      actuallyGetJSON('/static/callgraph.json',
      function (cg) { k(meta,reals,cg); })
      .fail(function() { 'failed to get callgraph' });
    });
  })
  .fail(function() { 'failed to get metadata' });
}


function getRealName(realNames,f) {
  var name = realNames[f];
  if (name === undefined) name = f;
  return name;
}


/* Note [Maps]

When the sepecs say that return `Map a b`, this means
that we are returning an object, where the keys look like `a`,
and the values look like `b`.
*/


/* Return information about the functions, the groups in them,
    and the number of tasks with various statuses.

Format: (see Note [Maps])
  Map <fun_name> { areaSet: Set areas
                 , groupMap: (Map <group_name> (Map <queue_name> number))
                 }
*/
function getGroupsMeta(meta) {
  var db = {};
  jQuery.each(meta,   function(q, q_info) {
  jQuery.each(q_info, function(a, a_info) {
  jQuery.each(a_info, function(f, f_info) {
  jQuery.each(f_info, function(g, g_info) {
  jQuery.each(g_info, function(u, tasks) {
    if (db[f] === undefined) db[f] = {};

    if (db[f][g] === undefined) db[f][g] = { areaSet: {}, qs: {} };
    db[f][g].areaSet[a] = true;
    if (db[f][g].qs[q] === undefined) db[f][g].qs[q] = 0;
    ++db[f][g].qs[q];
  });});});});});

  return db;
}



/* Return all tasks sorted by group.
Format: (see Note [Maps])

  Map <area_name>
     { taskStatus: <"solved" | "unsolved" | "bad">
     , taskName:   { function: <fun_name>
                   , group:    <group_name>
                   , task:     <task_name>
     }
*/
function getTasksByArea (meta) {
  var out = {};

  jQuery.each(meta,   function (q_name, areas)  {
  jQuery.each(areas,  function (a_name, funs)   {
  jQuery.each(funs,   function (f_name, groups) {
  jQuery.each(groups, function (g_name, tasks)  {
  jQuery.each(tasks,  function (unused, t_name) {
    if (out[a_name] === undefined) out[a_name] = [];
    out[a_name].push( { taskStatus: q_name
                      , taskName:   { function: f_name
                                    , group:    g_name
                                    , name:     t_name
                                    }
                      } );
  });});});});});

  return out;
}


// Find all the tasks for this task group.
// See `getTasksByArea` for the format of the result.
function getTasksForGroup (meta, fun, grp) {
  var allTasks = getTasksByArea (meta);
  var out = {};

  jQuery.each(allTasks, function(a_name, tasks) {
  jQuery.each(tasks,    function(unused, task)  {
    var tn = task.taskName;
    if (! (tn.function === fun && tn.group === grp)) return true;
    if (out[a_name] === undefined) out[a_name] = [];
    out[a_name].push(task);
  });});

  return out;
}


