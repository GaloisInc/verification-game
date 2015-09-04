
var worldOffset = 100;

function newWorld () {
  var blocks3d = {};
  var blocks2d = {};
  var minX, minY, minZ, maxX, maxY, maxZ;

  var me = {};

  var verbose = false;

  me.verbose = function (yes) { verbose = yes; };

  me.getDims = function() {
    return { min: { x: minX, y: minY, z: minZ }
           , max: { x: maxZ, y: maxY, z: maxZ }
           };
  };

  me.each = function(f) {
    jQuery.each(blocks3d, function(x,arrX) {
      jQuery.each(arrX, function(y,arrY) {
        jQuery.each(arrY, function(z,block) {
          f(x,y,z,arrY[z]);
        });
      });
    });
  };

  // Make a new block, and add it to the world. Returns the new block;
  me.newBlock = function(name, x, y, z) {
      var isTall = false;
      switch (name) {
        case 'Door_Tall_Closed':
        case 'Stone_Block_Tall':
        case 'Wall_Block_Tall':
        case 'Window_Tall':
          isTall = true;
      }

      var b =
        { name: name
        , dom: $('<img/>')
                .attr('src', '/static/img/PlanetCute_PNG/' + name + '.png')
         , x: x
         , y: y
         , z: z
         , updX: 0
         , updY: 0
         , isTall: isTall
         , items: []
         };
      me.setBlock(b);
      return b;
  };


  // Add a block to the world.  This will overwrite a previously existing
  // block, although the old block is not removed from the DOM.
  me.setBlock = function setBlock(block) {
    var x = block.x;
    var y = block.y;
    var z = block.z;

    // Updated 3d map
    if (blocks3d[x]    === undefined) blocks3d[x]    = {};
    if (blocks3d[x][y] === undefined) blocks3d[x][y] = {};
    blocks3d[x][y][z] = block;

    // Update boundaries
    if (minX === undefined || minX > x) minX = x;
    if (minY === undefined || minY > y) minY = y;
    if (minZ === undefined || minZ > z) minZ = z;
    if (maxX === undefined || maxX < x) maxX = x;
    if (maxY === undefined || maxY < y) maxY = y;
    if (maxZ === undefined || maxZ < z) maxZ = z;

    // Update 2d map
    if (blocks2d[x] === undefined) blocks2d[x]   = {};
    var mp      = blocks2d[x];
    var y2d     = 2 * y - z;
    var y2d_end = y2d + 2;
    if (block.isTall) y2d--;
    while (y2d <= y2d_end) {
      if (mp[y2d] === undefined) { mp[y2d] = {} }
      // We use the `lab` here, so that if a block is over-written in the
      // 3d map, it will be over-written here also.
      var lab = 'l' + block.x + '_' + block.y + '_' + block.z;
      mp[y2d][lab] = block;
      ++y2d;
    }
  };


  // Remove the block at the given position.
  // The block is returned as the result,
  // or `null` if no such block was there.
  me.rmBlock = function rmBlock(x,y,z,rmDom) {
    // Update 3d map
    var arr = blocks3d[x];
    if (arr === undefined) return null;
    arr = arr[y];
    if (arr === undefined) return null;
    var b = arr[z];
    if (b === undefined) return null;
    delete arr[z];

    // Update 2d map
    var mp      = blocks2d[x];
    var y2d     = 2 * y - z;
    var y2d_end = y2d + 2;
    if (b.isTall) y2d--;
    while (y2d <= y2d_end) {
      var lab = 'l' + b.x + '_' + b.y + '_' + b.z;
      delete mp[y2d][lab];
      ++y2d;
    }

    function cleanUp(ix,b) {
      b.dom.remove();
      jQuery.each(b.items, cleanUp);
    }

    if (rmDom) cleanUp(0,b);

    return b;
  };


  // Return the block occupping the given 2d position, or `null` if none.
  me.blockFrom2d = function (x2d, y2d) {
    var x  = Math.floor(x2d / 100);
    var xs = blocks2d[x];
    if (xs === undefined) return null;

    var y  = Math.floor( (y2d - 50 - worldOffset) / 40 );
    var ys = xs[y];
    if (ys === undefined) return null;

    var highest = null;
    jQuery.each(ys, function(ix,block) {
      if (highest    === null) { highest = block; return; }
      if (blockZindex(block) > blockZindex(highest)) highest = block;
    });

    return highest;
  };


  // Move out the blocks from the given area into a new world.
  // The last argument specifies if the blocks are removed from the DOM.
  me.moveOut = function(x1,y1,z1, x2,y2,z2, rmDom) {
    var w = newWorld();
    for (x = x1; x <= x2; ++x) {
      for (y = y1; y <= y2; ++y) {
        for (z = z1; z <= z2; ++z) {
          var block = me.rmBlock(x,y,z,rmDom);
          if (block !== null) w.setBlock(block);
        }
      }
    }
    return w;
  };

  // Copy the blocks for the given world into ours
  // Their origin (i.e., (0,0,0)) is at our (x,y,z).
  me.copyWorld = function (roWorld, x, y, z) {
    jQuery.each(roWorld.getBlocks3d(), function(_x,arrX) {
      jQuery.each(arrX, function(_y,arrY) {
        jQuery.each(arrY, function(_z,block) {
          me.setBlock(jQuery.extend({}, block, { x: block.x + x
                                               , y: block.y + y
                                               , z: block.z + z }));
        });
      });
    });
  };

  // Get the array of 3d blocks.
  // WARNING:  Avoid modifying directly, less we cofuse ourselves!
  me.getBlocks3d = function () { return blocks3d; };

  // Append the blocks in this world to the given element in the DOM
  me.draw = function (here) {
   jQuery.each(blocks3d, function(x,xs) {
     jQuery.each(xs, function(y,ys) {
        jQuery.each(ys, function(z,block) {
          blockDraw(block, here);
        });
      });
    });

    var curBlock = null;
    here
      .mousemove(function(ev) {
        var b = me.blockFrom2d(ev.pageX, ev.pageY);
        if (b === curBlock) return;
        if (curBlock !== null) {
          if (curBlock.mouseleave !== undefined) curBlock.mouseleave();
        }
        curBlock = b;
        if (curBlock !== null) {
          if (curBlock.mouseenter !== undefined) b.mouseenter();
        }
      })
      .click(function() {
        var b = curBlock;
        if (b !== null && b.click !== undefined) b.click();
      });
  };

  return me;
}



// -----------------------------------------------------------------------------
// Block stuff

function itemSideText(text,n) {
  if (n === undefined) n = 1;
  var margin = 5;

  return { dom: $('<div/>')
                 .text(text)
                 .css('background-color', '#cc9')
                 .css('border', '1px solid black')
                 .css('width', 100 * n - 2 * margin)
                 .css('height', '22')
                 .css('font-size', '16')
                 .css('text-align', 'center')
                 // .css('overflow-x', 'auto')
                 .css('padding-top', '7px')
                 .css('opacity', '0.5')
         , updX: margin
         , updY: 55
         , items: []
         , isTall: false
         , x: 0
         , y: 1
         , z: 0
         , name: "side-text"
         };
}

function itemTopText(text) {
  var margin = 5;
  return { dom: $('<div/>')
                .text(text)
                .css('background-color', '#cc9')
                .css('border', '1px solid black')
                .css('width', 100 - 2 * margin - 2)
                .css('height', '60')
                .css('font-size', '16')
                .css('text-align', 'center')
                .css('padding-top', '7px')
                .css('opacity', '0.8')
         , updX: margin
         , updY: 95
         , x: 0
         , y: 0
         , z: 1
         , isTall: false
         , items: []
         };
 }



function itemPQ(name,x,y,z) {
  return { dom: $('<img/>')
                .attr('src', '/static/img/PlanetCute_PNG/' + name + '.png')
         , name: name
         , updX: 0
         , updY: 0
         , x:x
         , y:y
         , z:z
         , isTall: false
         , items: []
         };
}

function itemSpeech(text) {
  var pic = $('<img/>')
            .attr('src', '/static/img/PlanetCute_PNG/SpeechBubble.png')
            .css('position', 'relative')
            .css('top', '0')
            .css('left', '0');

  return { dom: $('<div/>')
                 .append(pic)
                 .append($('<div/>')
                         .text(text)
                         .css('position', 'absolute')
                         .css('top', '80')
                         .css('left', '10')
                         .css('width', '90')
                         .css('height', '70')
                         .css('font-size', '16')
                         .css('overflow-y', 'auto'))
         , updX: 0
         , updY: 0
         , x: 1
         , y: 0
         , z: 2
         , isTall: false
         , items: []
         };
 }









function blockX(block) { return 100 * block.x + block.updX; }
function blockY(block) {
  return worldOffset + 80 * block.y - 40 * block.z + block.updY;
}
function blockZindex(block) { return 2 * block.y + block.z; }

function blockDraw(block, here) {

  var screenY = blockY(block);

  jQuery.each(block.items, function(ix,item) {
    var b1 = jQuery.extend({}, item, { x: block.x + item.x
                                     , y: block.y + item.y
                                     , z: block.z + item.z
                                     });
    blockDraw(b1, here);
  });



  block.dom.css('position', 'absolute')
           .css('left',      blockX(block))
           .css('top',       screenY)
           .zIndex(block.important ? 9999 : blockZindex(block));

  if (block.name === 'Water_Block') {
    block.dom.css('opacity', 0.8);
    animateWater(1);
  }

  here.append(block.dom);


  return;

  function animateWater(dir) {
    block.dom.animate
      ( { top: screenY + dir }
      , 6000 / (1 + (block.x % 4) + (block.y % 4))
      , 'swing'
      , function() { animateWater(-dir); }
      );
  }

}


