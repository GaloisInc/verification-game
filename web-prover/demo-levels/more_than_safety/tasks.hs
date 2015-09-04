TaskGroupData
  { tgdPreds =
      LevelPreds
        { lpredPre =
            NameT
              { nameTName = "p_galois'more_than_safety'P"
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
        , lpredLoops = []
        , lpredPost =
            NameT
              { nameTName = "p_galois'more_than_safety'Q"
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
                              { nameTName = "p_galois'more_than_safety'a_loop'C1P"
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
                              { nameTName = "p_galois'more_than_safety'a_loop'C1Q"
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
                ( "VCmore_than_safety_assert_galois_decorator" , "WP" )
            , gVars =
                [ ( "size_0" , TyCon "int" [] )
                , ( "malloc_0" , TyCon "map" [ TyCon "int" [] , TyCon "int" [] ] )
                , ( "mchar_0" , TyCon "map" [ TyCon "addr" [] , TyCon "int" [] ] )
                , ( "mint_0" , TyCon "map" [ TyCon "addr" [] , TyCon "int" [] ] )
                , ( "mptr_0" , TyCon "map" [ TyCon "addr" [] , TyCon "addr" [] ] )
                , ( "buf_0" , TyCon "addr" [] )
                ]
            , gDefs = []
            , gAsmps =
                [ "p_galois'more_than_safety'P malloc_0 mptr_0 mchar_0 mint_0 buf_0\n                            size_0"
                , "size_0 < 4294967296"
                , "0 <= size_0"
                , "sconst mchar_0"
                , "linked malloc_0"
                , "framed mptr_0"
                ]
            , gConc =
                "p_galois'more_than_safety'a_loop'C1P malloc_0 mptr_0 mchar_0 mint_0\n                                     buf_0 size_0"
            }
        , G { gName = ( "VCmore_than_safety_assert_rte_mem_access" , "WP" )
            , gVars =
                [ ( "size_0" , TyCon "int" [] )
                , ( "malloc_1" , TyCon "map" [ TyCon "int" [] , TyCon "int" [] ] )
                , ( "malloc_0" , TyCon "map" [ TyCon "int" [] , TyCon "int" [] ] )
                , ( "mchar_1" , TyCon "map" [ TyCon "addr" [] , TyCon "int" [] ] )
                , ( "mchar_0" , TyCon "map" [ TyCon "addr" [] , TyCon "int" [] ] )
                , ( "mint_1" , TyCon "map" [ TyCon "addr" [] , TyCon "int" [] ] )
                , ( "mint_0" , TyCon "map" [ TyCon "addr" [] , TyCon "int" [] ] )
                , ( "mptr_1" , TyCon "map" [ TyCon "addr" [] , TyCon "addr" [] ] )
                , ( "mptr_0" , TyCon "map" [ TyCon "addr" [] , TyCon "addr" [] ] )
                , ( "buf_0" , TyCon "addr" [] )
                ]
            , gDefs = []
            , gAsmps =
                [ "sconst mchar_0"
                , "linked malloc_0"
                , "framed mptr_0"
                , "p_galois'more_than_safety'a_loop'C1P malloc_0 mptr_0 mchar_0 mint_0\n                                     buf_0 size_0"
                , "p_galois'more_than_safety'P malloc_0 mptr_0 mchar_0 mint_0 buf_0\n                            size_0"
                , "p_galois'more_than_safety'a_loop'C1Q malloc_1 mptr_1 mchar_1 mint_1\n                                     malloc_0 mptr_0 mchar_0 mint_0 buf_0 size_0"
                , "size_0 < 4294967296"
                , "0 <= size_0"
                ]
            , gConc = "0 <= offset buf_0 + to_uint32 (size_0 - 1)"
            }
        , G { gName = ( "VCmore_than_safety_assert_rte_mem_access" , "WP" )
            , gVars =
                [ ( "size_0" , TyCon "int" [] )
                , ( "malloc_1" , TyCon "map" [ TyCon "int" [] , TyCon "int" [] ] )
                , ( "malloc_0" , TyCon "map" [ TyCon "int" [] , TyCon "int" [] ] )
                , ( "mchar_1" , TyCon "map" [ TyCon "addr" [] , TyCon "int" [] ] )
                , ( "mchar_0" , TyCon "map" [ TyCon "addr" [] , TyCon "int" [] ] )
                , ( "mint_1" , TyCon "map" [ TyCon "addr" [] , TyCon "int" [] ] )
                , ( "mint_0" , TyCon "map" [ TyCon "addr" [] , TyCon "int" [] ] )
                , ( "mptr_1" , TyCon "map" [ TyCon "addr" [] , TyCon "addr" [] ] )
                , ( "mptr_0" , TyCon "map" [ TyCon "addr" [] , TyCon "addr" [] ] )
                , ( "buf_0" , TyCon "addr" [] )
                ]
            , gDefs = []
            , gAsmps =
                [ "size_0 < 4294967296"
                , "0 <= size_0"
                , "sconst mchar_0"
                , "linked malloc_0"
                , "framed mptr_0"
                , "p_galois'more_than_safety'a_loop'C1P malloc_0 mptr_0 mchar_0 mint_0\n                                     buf_0 size_0"
                , "p_galois'more_than_safety'P malloc_0 mptr_0 mchar_0 mint_0 buf_0\n                            size_0"
                , "p_galois'more_than_safety'a_loop'C1Q malloc_1 mptr_1 mchar_1 mint_1\n                                     malloc_0 mptr_0 mchar_0 mint_0 buf_0 size_0"
                ]
            , gConc = "0 < base buf_0"
            }
        , G { gName = ( "VCmore_than_safety_assert_rte_mem_access" , "WP" )
            , gVars =
                [ ( "size_0" , TyCon "int" [] )
                , ( "malloc_1" , TyCon "map" [ TyCon "int" [] , TyCon "int" [] ] )
                , ( "malloc_0" , TyCon "map" [ TyCon "int" [] , TyCon "int" [] ] )
                , ( "mchar_1" , TyCon "map" [ TyCon "addr" [] , TyCon "int" [] ] )
                , ( "mchar_0" , TyCon "map" [ TyCon "addr" [] , TyCon "int" [] ] )
                , ( "mint_1" , TyCon "map" [ TyCon "addr" [] , TyCon "int" [] ] )
                , ( "mint_0" , TyCon "map" [ TyCon "addr" [] , TyCon "int" [] ] )
                , ( "mptr_1" , TyCon "map" [ TyCon "addr" [] , TyCon "addr" [] ] )
                , ( "mptr_0" , TyCon "map" [ TyCon "addr" [] , TyCon "addr" [] ] )
                , ( "buf_0" , TyCon "addr" [] )
                ]
            , gDefs = []
            , gAsmps =
                [ "sconst mchar_0"
                , "linked malloc_0"
                , "framed mptr_0"
                , "p_galois'more_than_safety'a_loop'C1P malloc_0 mptr_0 mchar_0 mint_0\n                                     buf_0 size_0"
                , "p_galois'more_than_safety'P malloc_0 mptr_0 mchar_0 mint_0 buf_0\n                            size_0"
                , "p_galois'more_than_safety'a_loop'C1Q malloc_1 mptr_1 mchar_1 mint_1\n                                     malloc_0 mptr_0 mchar_0 mint_0 buf_0 size_0"
                , "size_0 < 4294967296"
                , "0 <= size_0"
                ]
            , gConc =
                "offset buf_0 + to_uint32 (size_0 - 1) + 1 <= malloc_1[base buf_0]"
            }
        , G { gName = ( "VCmore_than_safety_post" , "WP" )
            , gVars =
                [ ( "size_0" , TyCon "int" [] )
                , ( "malloc_1" , TyCon "map" [ TyCon "int" [] , TyCon "int" [] ] )
                , ( "malloc_0" , TyCon "map" [ TyCon "int" [] , TyCon "int" [] ] )
                , ( "mchar_1" , TyCon "map" [ TyCon "addr" [] , TyCon "int" [] ] )
                , ( "mchar_0" , TyCon "map" [ TyCon "addr" [] , TyCon "int" [] ] )
                , ( "mint_1" , TyCon "map" [ TyCon "addr" [] , TyCon "int" [] ] )
                , ( "mint_0" , TyCon "map" [ TyCon "addr" [] , TyCon "int" [] ] )
                , ( "mptr_1" , TyCon "map" [ TyCon "addr" [] , TyCon "addr" [] ] )
                , ( "mptr_0" , TyCon "map" [ TyCon "addr" [] , TyCon "addr" [] ] )
                , ( "buf_0" , TyCon "addr" [] )
                ]
            , gDefs = [ ( "cse_0" , "size_0 - 1" ) ]
            , gAsmps =
                [ "p_galois'more_than_safety'a_loop'C1P malloc_0 mptr_0 mchar_0 mint_0\n                                     buf_0 size_0"
                , "p_galois'more_than_safety'P malloc_0 mptr_0 mchar_0 mint_0 buf_0\n                            size_0"
                , "p_galois'more_than_safety'a_loop'C1Q malloc_1 mptr_1 mchar_1 mint_1\n                                     malloc_0 mptr_0 mchar_0 mint_0 buf_0 size_0"
                , "offset buf_0 + to_uint32 cse_0 + 1 <= malloc_1[base buf_0]"
                , "0 <= offset buf_0 + to_uint32 cse_0"
                , "0 < base buf_0"
                , "size_0 < 4294967296"
                , "0 <= size_0"
                , "sconst mchar_0"
                , "linked malloc_0"
                , "framed mptr_0"
                ]
            , gConc =
                "p_galois'more_than_safety'Q malloc_1 mptr_1 mchar_1\n                            mint_1[shift buf_0 cse_0 <- 0] malloc_0 mptr_0 mchar_0 mint_0 buf_0\n                            size_0"
            }
        ]
  , tgdRoots = [ Concrete 0 , Concrete 1 , Concrete 2 , Post 3 ]
  , tgdGraph =
      fromList
        [ ( Concrete 0
          , [ ( 1
              , Other
                  (CallUInput
                     "a_loop"
                     NameT
                       { nameTName = "p_galois'more_than_safety'a_loop'C1P"
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
                       { nameTName = "p_galois'more_than_safety'a_loop'C1Q"
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
        , ( Concrete 1
          , [ ( 2
              , Other
                  (CallUInput
                     "a_loop"
                     NameT
                       { nameTName = "p_galois'more_than_safety'a_loop'C1P"
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
                       { nameTName = "p_galois'more_than_safety'a_loop'C1Q"
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
        , ( Concrete 2
          , [ ( 3
              , Other
                  (CallUInput
                     "a_loop"
                     NameT
                       { nameTName = "p_galois'more_than_safety'a_loop'C1P"
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
                       { nameTName = "p_galois'more_than_safety'a_loop'C1Q"
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
        , ( Post 3
          , [ ( 4
              , Other
                  (CallUInput
                     "a_loop"
                     NameT
                       { nameTName = "p_galois'more_than_safety'a_loop'C1P"
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
                       { nameTName = "p_galois'more_than_safety'a_loop'C1Q"
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
                   { nameTName = "p_galois'more_than_safety'P"
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
                   })
          , []
          )
        , ( Other
              (CallUInput
                 "a_loop"
                 NameT
                   { nameTName = "p_galois'more_than_safety'a_loop'C1P"
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
                   { nameTName = "p_galois'more_than_safety'a_loop'C1Q"
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
                       { nameTName = "p_galois'more_than_safety'P"
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
                       })
              )
            ]
          )
        ]
  }