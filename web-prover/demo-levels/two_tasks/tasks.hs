TaskGroupData
  { tgdPreds =
      LevelPreds
        { lpredPre =
            NameT
              { nameTName = "p_galois'two_tasks'P"
              , nameTParams =
                  [ TyCon "map" [ TyCon "int" [] , TyCon "int" [] ]
                  , TyCon "map" [ TyCon "addr" [] , TyCon "addr" [] ]
                  , TyCon "map" [ TyCon "addr" [] , TyCon "int" [] ]
                  , TyCon "map" [ TyCon "addr" [] , TyCon "int" [] ]
                  , TyCon "addr" []
                  , TyCon "addr" []
                  ]
              , nameTCTypes =
                  [ CType { ctPtrDepth = 1 , ctBaseType = 7 }
                  , CType { ctPtrDepth = 1 , ctBaseType = 7 }
                  ]
              }
        , lpredLoops = []
        , lpredPost =
            NameT
              { nameTName = "p_galois'two_tasks'Q"
              , nameTParams =
                  [ TyCon "map" [ TyCon "int" [] , TyCon "int" [] ]
                  , TyCon "map" [ TyCon "addr" [] , TyCon "addr" [] ]
                  , TyCon "map" [ TyCon "addr" [] , TyCon "int" [] ]
                  , TyCon "map" [ TyCon "addr" [] , TyCon "int" [] ]
                  , TyCon "map" [ TyCon "int" [] , TyCon "int" [] ]
                  , TyCon "map" [ TyCon "addr" [] , TyCon "addr" [] ]
                  , TyCon "map" [ TyCon "addr" [] , TyCon "int" [] ]
                  , TyCon "map" [ TyCon "addr" [] , TyCon "int" [] ]
                  , TyCon "addr" []
                  , TyCon "addr" []
                  ]
              , nameTCTypes =
                  [ CType { ctPtrDepth = 1 , ctBaseType = 7 }
                  , CType { ctPtrDepth = 1 , ctBaseType = 7 }
                  ]
              }
        , lpredCalls = fromList []
        }
  , tgdGoals =
      fromList
        [ G { gName = ( "VCtwo_tasks_assert_rte_mem_access" , "WP" )
            , gVars =
                [ ( "malloc_0" , TyCon "map" [ TyCon "int" [] , TyCon "int" [] ] )
                , ( "mchar_0" , TyCon "map" [ TyCon "addr" [] , TyCon "int" [] ] )
                , ( "mint_0" , TyCon "map" [ TyCon "addr" [] , TyCon "int" [] ] )
                , ( "mptr_0" , TyCon "map" [ TyCon "addr" [] , TyCon "addr" [] ] )
                , ( "x_0" , TyCon "addr" [] )
                , ( "y_0" , TyCon "addr" [] )
                ]
            , gDefs = []
            , gAsmps =
                [ "sconst mchar_0"
                , "linked malloc_0"
                , "framed mptr_0"
                , "p_galois'two_tasks'P malloc_0 mptr_0 mchar_0 mint_0 x_0 y_0"
                ]
            , gConc = "0 <= offset x_0"
            }
        , G { gName = ( "VCtwo_tasks_assert_rte_mem_access_2" , "WP" )
            , gVars =
                [ ( "malloc_0" , TyCon "map" [ TyCon "int" [] , TyCon "int" [] ] )
                , ( "mchar_0" , TyCon "map" [ TyCon "addr" [] , TyCon "int" [] ] )
                , ( "mint_0" , TyCon "map" [ TyCon "addr" [] , TyCon "int" [] ] )
                , ( "mptr_0" , TyCon "map" [ TyCon "addr" [] , TyCon "addr" [] ] )
                , ( "x_0" , TyCon "addr" [] )
                , ( "y_0" , TyCon "addr" [] )
                ]
            , gDefs = []
            , gAsmps =
                [ "offset x_0 + 1 <= malloc_0[base x_0]"
                , "0 <= offset x_0"
                , "0 < base x_0"
                , "sconst mchar_0"
                , "linked malloc_0"
                , "framed mptr_0"
                , "p_galois'two_tasks'P malloc_0 mptr_0 mchar_0 mint_0 x_0 y_0"
                ]
            , gConc = "0 < base y_0"
            }
        , G { gName = ( "VCtwo_tasks_assert_rte_mem_access" , "WP" )
            , gVars =
                [ ( "malloc_0" , TyCon "map" [ TyCon "int" [] , TyCon "int" [] ] )
                , ( "mchar_0" , TyCon "map" [ TyCon "addr" [] , TyCon "int" [] ] )
                , ( "mint_0" , TyCon "map" [ TyCon "addr" [] , TyCon "int" [] ] )
                , ( "mptr_0" , TyCon "map" [ TyCon "addr" [] , TyCon "addr" [] ] )
                , ( "x_0" , TyCon "addr" [] )
                , ( "y_0" , TyCon "addr" [] )
                ]
            , gDefs = []
            , gAsmps =
                [ "sconst mchar_0"
                , "framed mptr_0"
                , "p_galois'two_tasks'P malloc_0 mptr_0 mchar_0 mint_0 x_0 y_0"
                , "linked malloc_0"
                ]
            , gConc = "offset x_0 + 1 <= malloc_0[base x_0]"
            }
        , G { gName = ( "VCtwo_tasks_assert_rte_mem_access" , "WP" )
            , gVars =
                [ ( "malloc_0" , TyCon "map" [ TyCon "int" [] , TyCon "int" [] ] )
                , ( "mchar_0" , TyCon "map" [ TyCon "addr" [] , TyCon "int" [] ] )
                , ( "mint_0" , TyCon "map" [ TyCon "addr" [] , TyCon "int" [] ] )
                , ( "mptr_0" , TyCon "map" [ TyCon "addr" [] , TyCon "addr" [] ] )
                , ( "x_0" , TyCon "addr" [] )
                , ( "y_0" , TyCon "addr" [] )
                ]
            , gDefs = []
            , gAsmps =
                [ "sconst mchar_0"
                , "linked malloc_0"
                , "framed mptr_0"
                , "p_galois'two_tasks'P malloc_0 mptr_0 mchar_0 mint_0 x_0 y_0"
                ]
            , gConc = "0 < base x_0"
            }
        , G { gName = ( "VCtwo_tasks_assert_rte_mem_access_2" , "WP" )
            , gVars =
                [ ( "malloc_0" , TyCon "map" [ TyCon "int" [] , TyCon "int" [] ] )
                , ( "mchar_0" , TyCon "map" [ TyCon "addr" [] , TyCon "int" [] ] )
                , ( "mint_0" , TyCon "map" [ TyCon "addr" [] , TyCon "int" [] ] )
                , ( "mptr_0" , TyCon "map" [ TyCon "addr" [] , TyCon "addr" [] ] )
                , ( "x_0" , TyCon "addr" [] )
                , ( "y_0" , TyCon "addr" [] )
                ]
            , gDefs = []
            , gAsmps =
                [ "offset x_0 + 1 <= malloc_0[base x_0]"
                , "0 <= offset x_0"
                , "0 < base x_0"
                , "sconst mchar_0"
                , "linked malloc_0"
                , "framed mptr_0"
                , "p_galois'two_tasks'P malloc_0 mptr_0 mchar_0 mint_0 x_0 y_0"
                ]
            , gConc = "0 <= offset y_0"
            }
        , G { gName = ( "VCtwo_tasks_assert_rte_mem_access_2" , "WP" )
            , gVars =
                [ ( "malloc_0" , TyCon "map" [ TyCon "int" [] , TyCon "int" [] ] )
                , ( "mchar_0" , TyCon "map" [ TyCon "addr" [] , TyCon "int" [] ] )
                , ( "mint_0" , TyCon "map" [ TyCon "addr" [] , TyCon "int" [] ] )
                , ( "mptr_0" , TyCon "map" [ TyCon "addr" [] , TyCon "addr" [] ] )
                , ( "x_0" , TyCon "addr" [] )
                , ( "y_0" , TyCon "addr" [] )
                ]
            , gDefs = []
            , gAsmps =
                [ "0 <= offset x_0"
                , "0 < base x_0"
                , "sconst mchar_0"
                , "framed mptr_0"
                , "p_galois'two_tasks'P malloc_0 mptr_0 mchar_0 mint_0 x_0 y_0"
                , "offset x_0 + 1 <= malloc_0[base x_0]"
                , "linked malloc_0"
                ]
            , gConc = "offset y_0 + 1 <= malloc_0[base y_0]"
            }
        , G { gName = ( "VCtwo_tasks_post" , "WP" )
            , gVars =
                [ ( "malloc_0" , TyCon "map" [ TyCon "int" [] , TyCon "int" [] ] )
                , ( "mchar_0" , TyCon "map" [ TyCon "addr" [] , TyCon "int" [] ] )
                , ( "mint_0" , TyCon "map" [ TyCon "addr" [] , TyCon "int" [] ] )
                , ( "mptr_0" , TyCon "map" [ TyCon "addr" [] , TyCon "addr" [] ] )
                , ( "x_0" , TyCon "addr" [] )
                , ( "y_0" , TyCon "addr" [] )
                ]
            , gDefs = []
            , gAsmps =
                [ "p_galois'two_tasks'P malloc_0 mptr_0 mchar_0 mint_0 x_0 y_0"
                , "offset y_0 + 1 <= malloc_0[base y_0]"
                , "0 <= offset y_0"
                , "0 < base y_0"
                , "offset x_0 + 1 <= malloc_0[base x_0]"
                , "0 <= offset x_0"
                , "0 < base x_0"
                , "sconst mchar_0"
                , "linked malloc_0"
                , "framed mptr_0"
                ]
            , gConc =
                "p_galois'two_tasks'Q malloc_0 mptr_0 mchar_0\n                     mint_0[x_0 <- 1][y_0 <- 2] malloc_0 mptr_0 mchar_0 mint_0 x_0 y_0"
            }
        ]
  , tgdRoots =
      [ Concrete 0
      , Concrete 1
      , Concrete 2
      , Concrete 3
      , Concrete 4
      , Concrete 5
      , Post 6
      ]
  , tgdGraph =
      fromList
        [ ( Concrete 0
          , [ ( 0
              , Other
                  (NormalUInput
                     NameT
                       { nameTName = "p_galois'two_tasks'P"
                       , nameTParams =
                           [ TyCon "map" [ TyCon "int" [] , TyCon "int" [] ]
                           , TyCon "map" [ TyCon "addr" [] , TyCon "addr" [] ]
                           , TyCon "map" [ TyCon "addr" [] , TyCon "int" [] ]
                           , TyCon "map" [ TyCon "addr" [] , TyCon "int" [] ]
                           , TyCon "addr" []
                           , TyCon "addr" []
                           ]
                       , nameTCTypes =
                           [ CType { ctPtrDepth = 1 , ctBaseType = 7 }
                           , CType { ctPtrDepth = 1 , ctBaseType = 7 }
                           ]
                       })
              )
            ]
          )
        , ( Concrete 1
          , [ ( 1
              , Other
                  (NormalUInput
                     NameT
                       { nameTName = "p_galois'two_tasks'P"
                       , nameTParams =
                           [ TyCon "map" [ TyCon "int" [] , TyCon "int" [] ]
                           , TyCon "map" [ TyCon "addr" [] , TyCon "addr" [] ]
                           , TyCon "map" [ TyCon "addr" [] , TyCon "int" [] ]
                           , TyCon "map" [ TyCon "addr" [] , TyCon "int" [] ]
                           , TyCon "addr" []
                           , TyCon "addr" []
                           ]
                       , nameTCTypes =
                           [ CType { ctPtrDepth = 1 , ctBaseType = 7 }
                           , CType { ctPtrDepth = 1 , ctBaseType = 7 }
                           ]
                       })
              )
            ]
          )
        , ( Concrete 2
          , [ ( 2
              , Other
                  (NormalUInput
                     NameT
                       { nameTName = "p_galois'two_tasks'P"
                       , nameTParams =
                           [ TyCon "map" [ TyCon "int" [] , TyCon "int" [] ]
                           , TyCon "map" [ TyCon "addr" [] , TyCon "addr" [] ]
                           , TyCon "map" [ TyCon "addr" [] , TyCon "int" [] ]
                           , TyCon "map" [ TyCon "addr" [] , TyCon "int" [] ]
                           , TyCon "addr" []
                           , TyCon "addr" []
                           ]
                       , nameTCTypes =
                           [ CType { ctPtrDepth = 1 , ctBaseType = 7 }
                           , CType { ctPtrDepth = 1 , ctBaseType = 7 }
                           ]
                       })
              )
            ]
          )
        , ( Concrete 3
          , [ ( 3
              , Other
                  (NormalUInput
                     NameT
                       { nameTName = "p_galois'two_tasks'P"
                       , nameTParams =
                           [ TyCon "map" [ TyCon "int" [] , TyCon "int" [] ]
                           , TyCon "map" [ TyCon "addr" [] , TyCon "addr" [] ]
                           , TyCon "map" [ TyCon "addr" [] , TyCon "int" [] ]
                           , TyCon "map" [ TyCon "addr" [] , TyCon "int" [] ]
                           , TyCon "addr" []
                           , TyCon "addr" []
                           ]
                       , nameTCTypes =
                           [ CType { ctPtrDepth = 1 , ctBaseType = 7 }
                           , CType { ctPtrDepth = 1 , ctBaseType = 7 }
                           ]
                       })
              )
            ]
          )
        , ( Concrete 4
          , [ ( 4
              , Other
                  (NormalUInput
                     NameT
                       { nameTName = "p_galois'two_tasks'P"
                       , nameTParams =
                           [ TyCon "map" [ TyCon "int" [] , TyCon "int" [] ]
                           , TyCon "map" [ TyCon "addr" [] , TyCon "addr" [] ]
                           , TyCon "map" [ TyCon "addr" [] , TyCon "int" [] ]
                           , TyCon "map" [ TyCon "addr" [] , TyCon "int" [] ]
                           , TyCon "addr" []
                           , TyCon "addr" []
                           ]
                       , nameTCTypes =
                           [ CType { ctPtrDepth = 1 , ctBaseType = 7 }
                           , CType { ctPtrDepth = 1 , ctBaseType = 7 }
                           ]
                       })
              )
            ]
          )
        , ( Concrete 5
          , [ ( 5
              , Other
                  (NormalUInput
                     NameT
                       { nameTName = "p_galois'two_tasks'P"
                       , nameTParams =
                           [ TyCon "map" [ TyCon "int" [] , TyCon "int" [] ]
                           , TyCon "map" [ TyCon "addr" [] , TyCon "addr" [] ]
                           , TyCon "map" [ TyCon "addr" [] , TyCon "int" [] ]
                           , TyCon "map" [ TyCon "addr" [] , TyCon "int" [] ]
                           , TyCon "addr" []
                           , TyCon "addr" []
                           ]
                       , nameTCTypes =
                           [ CType { ctPtrDepth = 1 , ctBaseType = 7 }
                           , CType { ctPtrDepth = 1 , ctBaseType = 7 }
                           ]
                       })
              )
            ]
          )
        , ( Post 6
          , [ ( 6
              , Other
                  (NormalUInput
                     NameT
                       { nameTName = "p_galois'two_tasks'P"
                       , nameTParams =
                           [ TyCon "map" [ TyCon "int" [] , TyCon "int" [] ]
                           , TyCon "map" [ TyCon "addr" [] , TyCon "addr" [] ]
                           , TyCon "map" [ TyCon "addr" [] , TyCon "int" [] ]
                           , TyCon "map" [ TyCon "addr" [] , TyCon "int" [] ]
                           , TyCon "addr" []
                           , TyCon "addr" []
                           ]
                       , nameTCTypes =
                           [ CType { ctPtrDepth = 1 , ctBaseType = 7 }
                           , CType { ctPtrDepth = 1 , ctBaseType = 7 }
                           ]
                       })
              )
            ]
          )
        , ( Other
              (NormalUInput
                 NameT
                   { nameTName = "p_galois'two_tasks'P"
                   , nameTParams =
                       [ TyCon "map" [ TyCon "int" [] , TyCon "int" [] ]
                       , TyCon "map" [ TyCon "addr" [] , TyCon "addr" [] ]
                       , TyCon "map" [ TyCon "addr" [] , TyCon "int" [] ]
                       , TyCon "map" [ TyCon "addr" [] , TyCon "int" [] ]
                       , TyCon "addr" []
                       , TyCon "addr" []
                       ]
                   , nameTCTypes =
                       [ CType { ctPtrDepth = 1 , ctBaseType = 7 }
                       , CType { ctPtrDepth = 1 , ctBaseType = 7 }
                       ]
                   })
          , []
          )
        ]
  }