TaskGroupData
  { tgdPreds =
      LevelPreds
        { lpredPre =
            NameT
              { nameTName = "p_galois'a_function_call'P"
              , nameTParams =
                  [ TyCon "map" [ TyCon "int" [] , TyCon "int" [] ]
                  , TyCon "map" [ TyCon "addr" [] , TyCon "addr" [] ]
                  , TyCon "map" [ TyCon "addr" [] , TyCon "int" [] ]
                  , TyCon "map" [ TyCon "addr" [] , TyCon "int" [] ]
                  ]
              , nameTCTypes = []
              }
        , lpredLoops = []
        , lpredPost =
            NameT
              { nameTName = "p_galois'a_function_call'Q"
              , nameTParams =
                  [ TyCon "map" [ TyCon "int" [] , TyCon "int" [] ]
                  , TyCon "map" [ TyCon "addr" [] , TyCon "addr" [] ]
                  , TyCon "map" [ TyCon "addr" [] , TyCon "int" [] ]
                  , TyCon "map" [ TyCon "addr" [] , TyCon "int" [] ]
                  , TyCon "map" [ TyCon "int" [] , TyCon "int" [] ]
                  , TyCon "map" [ TyCon "addr" [] , TyCon "addr" [] ]
                  , TyCon "map" [ TyCon "addr" [] , TyCon "int" [] ]
                  , TyCon "map" [ TyCon "addr" [] , TyCon "int" [] ]
                  ]
              , nameTCTypes = []
              }
        , lpredCalls =
            fromList
              [ ( "a_loop"
                , CallInfo
                    { lpredCallPre =
                        NameT
                          { nameTName = "p_galois'a_loop'P"
                          , nameTParams =
                              [ TyCon "map" [ TyCon "int" [] , TyCon "int" [] ]
                              , TyCon "map" [ TyCon "addr" [] , TyCon "addr" [] ]
                              , TyCon "map" [ TyCon "addr" [] , TyCon "int" [] ]
                              , TyCon "map" [ TyCon "addr" [] , TyCon "int" [] ]
                              , TyCon "addr" []
                              , TyCon "int" []
                              ]
                          , nameTCTypes =
                              [ CType { ctPtrDepth = 1 , ctBaseType = 7 }
                              , CType { ctPtrDepth = 0 , ctBaseType = 11 }
                              ]
                          }
                    , lpredCallPost =
                        NameT
                          { nameTName = "p_galois'a_loop'Q"
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
                              , TyCon "int" []
                              ]
                          , nameTCTypes =
                              [ CType { ctPtrDepth = 1 , ctBaseType = 7 }
                              , CType { ctPtrDepth = 0 , ctBaseType = 11 }
                              ]
                          }
                    , lpredCallSites =
                        [ ( NameT
                              { nameTName = "p_galois'a_function_call'a_loop'C1P"
                              , nameTParams =
                                  [ TyCon "map" [ TyCon "int" [] , TyCon "int" [] ]
                                  , TyCon "map" [ TyCon "addr" [] , TyCon "addr" [] ]
                                  , TyCon "map" [ TyCon "addr" [] , TyCon "int" [] ]
                                  , TyCon "map" [ TyCon "addr" [] , TyCon "int" [] ]
                                  , TyCon "addr" []
                                  , TyCon "int" []
                                  ]
                              , nameTCTypes =
                                  [ CType { ctPtrDepth = 1 , ctBaseType = 7 }
                                  , CType { ctPtrDepth = 0 , ctBaseType = 11 }
                                  ]
                              }
                          , NameT
                              { nameTName = "p_galois'a_function_call'a_loop'C1Q"
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
                                  , TyCon "int" []
                                  ]
                              , nameTCTypes =
                                  [ CType { ctPtrDepth = 1 , ctBaseType = 7 }
                                  , CType { ctPtrDepth = 0 , ctBaseType = 11 }
                                  ]
                              }
                          )
                        ]
                    }
                )
              ]
        }
  , tgdGoals =
      fromList
        [ G { gName =
                ( "VCa_function_call_assert_galois_decorator" , "WP" )
            , gVars =
                [ ( "malloc_0" , TyCon "map" [ TyCon "int" [] , TyCon "int" [] ] )
                , ( "mchar_0" , TyCon "map" [ TyCon "addr" [] , TyCon "int" [] ] )
                , ( "mint_0" , TyCon "map" [ TyCon "addr" [] , TyCon "int" [] ] )
                , ( "mptr_0" , TyCon "map" [ TyCon "addr" [] , TyCon "addr" [] ] )
                ]
            , gDefs = []
            , gAsmps =
                [ "p_galois'a_function_call'P malloc_0 mptr_0 mchar_0 mint_0"
                , "sconst mchar_0"
                , "linked malloc_0"
                , "framed mptr_0"
                ]
            , gConc =
                "p_galois'a_function_call'a_loop'C1P malloc_0[1160 <- 3] mptr_0\n                                    mchar_0 mint_0 (Mk_addr 1160 0) 3"
            }
        , G { gName = ( "VCa_function_call_post" , "WP" )
            , gVars =
                [ ( "malloc_1" , TyCon "map" [ TyCon "int" [] , TyCon "int" [] ] )
                , ( "malloc_0" , TyCon "map" [ TyCon "int" [] , TyCon "int" [] ] )
                , ( "mchar_1" , TyCon "map" [ TyCon "addr" [] , TyCon "int" [] ] )
                , ( "mchar_0" , TyCon "map" [ TyCon "addr" [] , TyCon "int" [] ] )
                , ( "mint_1" , TyCon "map" [ TyCon "addr" [] , TyCon "int" [] ] )
                , ( "mint_0" , TyCon "map" [ TyCon "addr" [] , TyCon "int" [] ] )
                , ( "mptr_1" , TyCon "map" [ TyCon "addr" [] , TyCon "addr" [] ] )
                , ( "mptr_0" , TyCon "map" [ TyCon "addr" [] , TyCon "addr" [] ] )
                ]
            , gDefs =
                [ ( "cse_1" , "Mk_addr 1160 0" )
                , ( "cse_2" , "malloc_1[1160 <- 3]" )
                ]
            , gAsmps =
                [ "p_galois'a_function_call'P malloc_1 mptr_0 mchar_0 mint_0"
                , "p_galois'a_function_call'a_loop'C1P cse_2 mptr_0 mchar_0 mint_0\n                                    cse_1 3"
                , "p_galois'a_function_call'a_loop'C1Q malloc_0 mptr_1 mchar_1 mint_1\n                                    cse_2 mptr_0 mchar_0 mint_0 cse_1 3"
                , "sconst mchar_0"
                , "linked malloc_1"
                , "framed mptr_0"
                ]
            , gConc =
                "p_galois'a_function_call'Q malloc_0[1160 <- 0] mptr_1 mchar_1\n                           mint_1 malloc_1 mptr_0 mchar_0 mint_0"
            }
        ]
  , tgdRoots =
      [ Other
          (CallUInput
             "a_loop"
             NameT
               { nameTName = "p_galois'a_function_call'a_loop'C1P"
               , nameTParams =
                   [ TyCon "map" [ TyCon "int" [] , TyCon "int" [] ]
                   , TyCon "map" [ TyCon "addr" [] , TyCon "addr" [] ]
                   , TyCon "map" [ TyCon "addr" [] , TyCon "int" [] ]
                   , TyCon "map" [ TyCon "addr" [] , TyCon "int" [] ]
                   , TyCon "addr" []
                   , TyCon "int" []
                   ]
               , nameTCTypes =
                   [ CType { ctPtrDepth = 1 , ctBaseType = 7 }
                   , CType { ctPtrDepth = 0 , ctBaseType = 11 }
                   ]
               }
             NameT
               { nameTName = "p_galois'a_function_call'a_loop'C1Q"
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
                   , TyCon "int" []
                   ]
               , nameTCTypes =
                   [ CType { ctPtrDepth = 1 , ctBaseType = 7 }
                   , CType { ctPtrDepth = 0 , ctBaseType = 11 }
                   ]
               })
      , Post 0
      ]
  , tgdGraph =
      fromList
        [ ( Post 0
          , [ ( 1
              , Other
                  (CallUInput
                     "a_loop"
                     NameT
                       { nameTName = "p_galois'a_function_call'a_loop'C1P"
                       , nameTParams =
                           [ TyCon "map" [ TyCon "int" [] , TyCon "int" [] ]
                           , TyCon "map" [ TyCon "addr" [] , TyCon "addr" [] ]
                           , TyCon "map" [ TyCon "addr" [] , TyCon "int" [] ]
                           , TyCon "map" [ TyCon "addr" [] , TyCon "int" [] ]
                           , TyCon "addr" []
                           , TyCon "int" []
                           ]
                       , nameTCTypes =
                           [ CType { ctPtrDepth = 1 , ctBaseType = 7 }
                           , CType { ctPtrDepth = 0 , ctBaseType = 11 }
                           ]
                       }
                     NameT
                       { nameTName = "p_galois'a_function_call'a_loop'C1Q"
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
                           , TyCon "int" []
                           ]
                       , nameTCTypes =
                           [ CType { ctPtrDepth = 1 , ctBaseType = 7 }
                           , CType { ctPtrDepth = 0 , ctBaseType = 11 }
                           ]
                       })
              )
            ]
          )
        , ( Other
              (NormalUInput
                 NameT
                   { nameTName = "p_galois'a_function_call'P"
                   , nameTParams =
                       [ TyCon "map" [ TyCon "int" [] , TyCon "int" [] ]
                       , TyCon "map" [ TyCon "addr" [] , TyCon "addr" [] ]
                       , TyCon "map" [ TyCon "addr" [] , TyCon "int" [] ]
                       , TyCon "map" [ TyCon "addr" [] , TyCon "int" [] ]
                       ]
                   , nameTCTypes = []
                   })
          , []
          )
        , ( Other
              (CallUInput
                 "a_loop"
                 NameT
                   { nameTName = "p_galois'a_function_call'a_loop'C1P"
                   , nameTParams =
                       [ TyCon "map" [ TyCon "int" [] , TyCon "int" [] ]
                       , TyCon "map" [ TyCon "addr" [] , TyCon "addr" [] ]
                       , TyCon "map" [ TyCon "addr" [] , TyCon "int" [] ]
                       , TyCon "map" [ TyCon "addr" [] , TyCon "int" [] ]
                       , TyCon "addr" []
                       , TyCon "int" []
                       ]
                   , nameTCTypes =
                       [ CType { ctPtrDepth = 1 , ctBaseType = 7 }
                       , CType { ctPtrDepth = 0 , ctBaseType = 11 }
                       ]
                   }
                 NameT
                   { nameTName = "p_galois'a_function_call'a_loop'C1Q"
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
                       , TyCon "int" []
                       ]
                   , nameTCTypes =
                       [ CType { ctPtrDepth = 1 , ctBaseType = 7 }
                       , CType { ctPtrDepth = 0 , ctBaseType = 11 }
                       ]
                   })
          , [ ( 0
              , Other
                  (NormalUInput
                     NameT
                       { nameTName = "p_galois'a_function_call'P"
                       , nameTParams =
                           [ TyCon "map" [ TyCon "int" [] , TyCon "int" [] ]
                           , TyCon "map" [ TyCon "addr" [] , TyCon "addr" [] ]
                           , TyCon "map" [ TyCon "addr" [] , TyCon "int" [] ]
                           , TyCon "map" [ TyCon "addr" [] , TyCon "int" [] ]
                           ]
                       , nameTCTypes = []
                       })
              )
            ]
          )
        ]
  }