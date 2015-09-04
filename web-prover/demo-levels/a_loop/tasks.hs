TaskGroupData
  { tgdPreds =
      LevelPreds
        { lpredPre =
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
        , lpredLoops =
            [ NameT
                { nameTName = "p_galois'a_loop'I1"
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
                    , TyCon "int" []
                    , TyCon "addr" []
                    , TyCon "int" []
                    ]
                , nameTCTypes =
                    [ CType { ctPtrDepth = 1 , ctBaseType = 7 }
                    , CType { ctPtrDepth = 0 , ctBaseType = 11 }
                    , CType { ctPtrDepth = 0 , ctBaseType = 11 }
                    , CType { ctPtrDepth = 1 , ctBaseType = 7 }
                    , CType { ctPtrDepth = 0 , ctBaseType = 11 }
                    ]
                }
            ]
        , lpredPost =
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
        , lpredCalls = fromList []
        }
  , tgdGoals =
      fromList
        [ G { gName =
                ( "VCa_loop_loop_inv_galois_decorator_preserved" , "WP" )
            , gVars =
                [ ( "i_0" , TyCon "int" [] )
                , ( "size_1" , TyCon "int" [] )
                , ( "size_0" , TyCon "int" [] )
                , ( "malloc_1" , TyCon "map" [ TyCon "int" [] , TyCon "int" [] ] )
                , ( "malloc_0" , TyCon "map" [ TyCon "int" [] , TyCon "int" [] ] )
                , ( "mchar_1" , TyCon "map" [ TyCon "addr" [] , TyCon "int" [] ] )
                , ( "mchar_0" , TyCon "map" [ TyCon "addr" [] , TyCon "int" [] ] )
                , ( "mint_1" , TyCon "map" [ TyCon "addr" [] , TyCon "int" [] ] )
                , ( "mint_0" , TyCon "map" [ TyCon "addr" [] , TyCon "int" [] ] )
                , ( "mptr_1" , TyCon "map" [ TyCon "addr" [] , TyCon "addr" [] ] )
                , ( "mptr_0" , TyCon "map" [ TyCon "addr" [] , TyCon "addr" [] ] )
                , ( "buf_1" , TyCon "addr" [] )
                , ( "buf_0" , TyCon "addr" [] )
                ]
            , gDefs =
                [ ( "cse_0" , "1 + i_0" ) , ( "cse_1" , "shift buf_0 i_0" ) ]
            , gAsmps =
                [ "p_galois'a_loop'P malloc_0 mptr_0 mchar_0 mint_1 buf_1 size_1"
                , "p_galois'a_loop'I1 malloc_1 mptr_1 mchar_1 mint_0 malloc_0 mptr_0\n                   mchar_0 mint_1 buf_1 size_1 i_0 buf_0 size_0"
                , "offset buf_0 + i_0 + 1 <= malloc_1[base buf_0]"
                , "0 <= offset buf_0 + i_0"
                , "0 < base buf_0"
                , "size_0 < 4294967296"
                , "size_1 < 4294967296"
                , "0 <= size_1"
                , "0 <= i_0"
                , "sconst mchar_0"
                , "linked malloc_0"
                , "framed mptr_0"
                , "i_0 < size_0"
                ]
            , gConc =
                "p_galois'a_loop'I1 malloc_1 mptr_1 mchar_1 mint_0[cse_1 <- 0]\n                   malloc_0 mptr_0 mchar_0 mint_1 buf_1 size_1 cse_0 buf_0 size_0"
            }
        , G { gName =
                ( "VCa_loop_loop_inv_galois_decorator_established" , "WP" )
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
                [ "p_galois'a_loop'P malloc_0 mptr_0 mchar_0 mint_0 buf_0 size_0"
                , "size_0 < 4294967296"
                , "0 <= size_0"
                , "sconst mchar_0"
                , "linked malloc_0"
                , "framed mptr_0"
                ]
            , gConc =
                "p_galois'a_loop'I1 malloc_0 mptr_0 mchar_0 mint_0 malloc_0 mptr_0\n                   mchar_0 mint_0 buf_0 size_0 0 buf_0 size_0"
            }
        , G { gName = ( "VCa_loop_assert_rte_mem_access" , "WP" )
            , gVars =
                [ ( "i_0" , TyCon "int" [] )
                , ( "size_1" , TyCon "int" [] )
                , ( "size_0" , TyCon "int" [] )
                , ( "malloc_1" , TyCon "map" [ TyCon "int" [] , TyCon "int" [] ] )
                , ( "malloc_0" , TyCon "map" [ TyCon "int" [] , TyCon "int" [] ] )
                , ( "mchar_1" , TyCon "map" [ TyCon "addr" [] , TyCon "int" [] ] )
                , ( "mchar_0" , TyCon "map" [ TyCon "addr" [] , TyCon "int" [] ] )
                , ( "mint_1" , TyCon "map" [ TyCon "addr" [] , TyCon "int" [] ] )
                , ( "mint_0" , TyCon "map" [ TyCon "addr" [] , TyCon "int" [] ] )
                , ( "mptr_1" , TyCon "map" [ TyCon "addr" [] , TyCon "addr" [] ] )
                , ( "mptr_0" , TyCon "map" [ TyCon "addr" [] , TyCon "addr" [] ] )
                , ( "buf_1" , TyCon "addr" [] )
                , ( "buf_0" , TyCon "addr" [] )
                ]
            , gDefs = []
            , gAsmps =
                [ "p_galois'a_loop'P malloc_0 mptr_1 mchar_1 mint_1 buf_1 size_1"
                , "size_0 < 4294967296"
                , "size_1 < 4294967296"
                , "0 <= size_1"
                , "sconst mchar_1"
                , "linked malloc_0"
                , "framed mptr_1"
                , "p_galois'a_loop'I1 malloc_1 mptr_0 mchar_0 mint_0 malloc_0 mptr_1\n                   mchar_1 mint_1 buf_1 size_1 i_0 buf_0 size_0"
                , "0 <= i_0"
                , "i_0 < size_0"
                ]
            , gConc = "offset buf_0 + i_0 + 1 <= malloc_1[base buf_0]"
            }
        , G { gName = ( "VCa_loop_assert_rte_mem_access" , "WP" )
            , gVars =
                [ ( "i_0" , TyCon "int" [] )
                , ( "size_1" , TyCon "int" [] )
                , ( "size_0" , TyCon "int" [] )
                , ( "malloc_1" , TyCon "map" [ TyCon "int" [] , TyCon "int" [] ] )
                , ( "malloc_0" , TyCon "map" [ TyCon "int" [] , TyCon "int" [] ] )
                , ( "mchar_1" , TyCon "map" [ TyCon "addr" [] , TyCon "int" [] ] )
                , ( "mchar_0" , TyCon "map" [ TyCon "addr" [] , TyCon "int" [] ] )
                , ( "mint_1" , TyCon "map" [ TyCon "addr" [] , TyCon "int" [] ] )
                , ( "mint_0" , TyCon "map" [ TyCon "addr" [] , TyCon "int" [] ] )
                , ( "mptr_1" , TyCon "map" [ TyCon "addr" [] , TyCon "addr" [] ] )
                , ( "mptr_0" , TyCon "map" [ TyCon "addr" [] , TyCon "addr" [] ] )
                , ( "buf_1" , TyCon "addr" [] )
                , ( "buf_0" , TyCon "addr" [] )
                ]
            , gDefs = []
            , gAsmps =
                [ "p_galois'a_loop'P malloc_0 mptr_1 mchar_1 mint_1 buf_1 size_1"
                , "size_0 < 4294967296"
                , "size_1 < 4294967296"
                , "0 <= size_1"
                , "sconst mchar_1"
                , "linked malloc_0"
                , "framed mptr_1"
                , "p_galois'a_loop'I1 malloc_1 mptr_0 mchar_0 mint_0 malloc_0 mptr_1\n                   mchar_1 mint_1 buf_1 size_1 i_0 buf_0 size_0"
                , "0 <= i_0"
                , "i_0 < size_0"
                ]
            , gConc = "0 <= offset buf_0 + i_0"
            }
        , G { gName = ( "VCa_loop_assert_rte_mem_access" , "WP" )
            , gVars =
                [ ( "i_0" , TyCon "int" [] )
                , ( "size_1" , TyCon "int" [] )
                , ( "size_0" , TyCon "int" [] )
                , ( "malloc_1" , TyCon "map" [ TyCon "int" [] , TyCon "int" [] ] )
                , ( "malloc_0" , TyCon "map" [ TyCon "int" [] , TyCon "int" [] ] )
                , ( "mchar_1" , TyCon "map" [ TyCon "addr" [] , TyCon "int" [] ] )
                , ( "mchar_0" , TyCon "map" [ TyCon "addr" [] , TyCon "int" [] ] )
                , ( "mint_1" , TyCon "map" [ TyCon "addr" [] , TyCon "int" [] ] )
                , ( "mint_0" , TyCon "map" [ TyCon "addr" [] , TyCon "int" [] ] )
                , ( "mptr_1" , TyCon "map" [ TyCon "addr" [] , TyCon "addr" [] ] )
                , ( "mptr_0" , TyCon "map" [ TyCon "addr" [] , TyCon "addr" [] ] )
                , ( "buf_1" , TyCon "addr" [] )
                , ( "buf_0" , TyCon "addr" [] )
                ]
            , gDefs = []
            , gAsmps =
                [ "p_galois'a_loop'P malloc_0 mptr_1 mchar_1 mint_1 buf_1 size_1"
                , "size_0 < 4294967296"
                , "size_1 < 4294967296"
                , "0 <= size_1"
                , "0 <= i_0"
                , "sconst mchar_1"
                , "linked malloc_0"
                , "framed mptr_1"
                , "i_0 < size_0"
                , "p_galois'a_loop'I1 malloc_1 mptr_0 mchar_0 mint_0 malloc_0 mptr_1\n                   mchar_1 mint_1 buf_1 size_1 i_0 buf_0 size_0"
                ]
            , gConc = "0 < base buf_0"
            }
        , G { gName = ( "VCa_loop_post" , "WP" )
            , gVars =
                [ ( "i_0" , TyCon "int" [] )
                , ( "size_1" , TyCon "int" [] )
                , ( "size_0" , TyCon "int" [] )
                , ( "malloc_1" , TyCon "map" [ TyCon "int" [] , TyCon "int" [] ] )
                , ( "malloc_0" , TyCon "map" [ TyCon "int" [] , TyCon "int" [] ] )
                , ( "mchar_1" , TyCon "map" [ TyCon "addr" [] , TyCon "int" [] ] )
                , ( "mchar_0" , TyCon "map" [ TyCon "addr" [] , TyCon "int" [] ] )
                , ( "mint_1" , TyCon "map" [ TyCon "addr" [] , TyCon "int" [] ] )
                , ( "mint_0" , TyCon "map" [ TyCon "addr" [] , TyCon "int" [] ] )
                , ( "mptr_1" , TyCon "map" [ TyCon "addr" [] , TyCon "addr" [] ] )
                , ( "mptr_0" , TyCon "map" [ TyCon "addr" [] , TyCon "addr" [] ] )
                , ( "buf_1" , TyCon "addr" [] )
                , ( "buf_0" , TyCon "addr" [] )
                ]
            , gDefs = []
            , gAsmps =
                [ "0 <= size_0"
                , "i_0 < 4294967296"
                , "size_0 <= i_0"
                , "p_galois'a_loop'P malloc_1 mptr_1 mchar_1 mint_1 buf_1 size_1"
                , "p_galois'a_loop'I1 malloc_0 mptr_0 mchar_0 mint_0 malloc_1 mptr_1\n                   mchar_1 mint_1 buf_1 size_1 i_0 buf_0 size_0"
                , "size_1 < 4294967296"
                , "0 <= size_1"
                , "sconst mchar_1"
                , "linked malloc_1"
                , "framed mptr_1"
                ]
            , gConc =
                "p_galois'a_loop'Q malloc_0 mptr_0 mchar_0 mint_0 malloc_1 mptr_1\n                  mchar_1 mint_1 buf_1 size_1"
            }
        ]
  , tgdRoots = [ Concrete 0 , Concrete 1 , Concrete 2 , Post 3 ]
  , tgdGraph =
      fromList
        [ ( Concrete 0
          , [ ( 2
              , Other
                  (NormalUInput
                     NameT
                       { nameTName = "p_galois'a_loop'I1"
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
                           , TyCon "int" []
                           , TyCon "addr" []
                           , TyCon "int" []
                           ]
                       , nameTCTypes =
                           [ CType { ctPtrDepth = 1 , ctBaseType = 7 }
                           , CType { ctPtrDepth = 0 , ctBaseType = 11 }
                           , CType { ctPtrDepth = 0 , ctBaseType = 11 }
                           , CType { ctPtrDepth = 1 , ctBaseType = 7 }
                           , CType { ctPtrDepth = 0 , ctBaseType = 11 }
                           ]
                       })
              )
            ]
          )
        , ( Concrete 1
          , [ ( 3
              , Other
                  (NormalUInput
                     NameT
                       { nameTName = "p_galois'a_loop'I1"
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
                           , TyCon "int" []
                           , TyCon "addr" []
                           , TyCon "int" []
                           ]
                       , nameTCTypes =
                           [ CType { ctPtrDepth = 1 , ctBaseType = 7 }
                           , CType { ctPtrDepth = 0 , ctBaseType = 11 }
                           , CType { ctPtrDepth = 0 , ctBaseType = 11 }
                           , CType { ctPtrDepth = 1 , ctBaseType = 7 }
                           , CType { ctPtrDepth = 0 , ctBaseType = 11 }
                           ]
                       })
              )
            ]
          )
        , ( Concrete 2
          , [ ( 4
              , Other
                  (NormalUInput
                     NameT
                       { nameTName = "p_galois'a_loop'I1"
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
                           , TyCon "int" []
                           , TyCon "addr" []
                           , TyCon "int" []
                           ]
                       , nameTCTypes =
                           [ CType { ctPtrDepth = 1 , ctBaseType = 7 }
                           , CType { ctPtrDepth = 0 , ctBaseType = 11 }
                           , CType { ctPtrDepth = 0 , ctBaseType = 11 }
                           , CType { ctPtrDepth = 1 , ctBaseType = 7 }
                           , CType { ctPtrDepth = 0 , ctBaseType = 11 }
                           ]
                       })
              )
            ]
          )
        , ( Post 3
          , [ ( 5
              , Other
                  (NormalUInput
                     NameT
                       { nameTName = "p_galois'a_loop'I1"
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
                           , TyCon "int" []
                           , TyCon "addr" []
                           , TyCon "int" []
                           ]
                       , nameTCTypes =
                           [ CType { ctPtrDepth = 1 , ctBaseType = 7 }
                           , CType { ctPtrDepth = 0 , ctBaseType = 11 }
                           , CType { ctPtrDepth = 0 , ctBaseType = 11 }
                           , CType { ctPtrDepth = 1 , ctBaseType = 7 }
                           , CType { ctPtrDepth = 0 , ctBaseType = 11 }
                           ]
                       })
              )
            ]
          )
        , ( Other
              (NormalUInput
                 NameT
                   { nameTName = "p_galois'a_loop'I1"
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
                       , TyCon "int" []
                       , TyCon "addr" []
                       , TyCon "int" []
                       ]
                   , nameTCTypes =
                       [ CType { ctPtrDepth = 1 , ctBaseType = 7 }
                       , CType { ctPtrDepth = 0 , ctBaseType = 11 }
                       , CType { ctPtrDepth = 0 , ctBaseType = 11 }
                       , CType { ctPtrDepth = 1 , ctBaseType = 7 }
                       , CType { ctPtrDepth = 0 , ctBaseType = 11 }
                       ]
                   })
          , [ ( 0
              , Other
                  (NormalUInput
                     NameT
                       { nameTName = "p_galois'a_loop'I1"
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
                           , TyCon "int" []
                           , TyCon "addr" []
                           , TyCon "int" []
                           ]
                       , nameTCTypes =
                           [ CType { ctPtrDepth = 1 , ctBaseType = 7 }
                           , CType { ctPtrDepth = 0 , ctBaseType = 11 }
                           , CType { ctPtrDepth = 0 , ctBaseType = 11 }
                           , CType { ctPtrDepth = 1 , ctBaseType = 7 }
                           , CType { ctPtrDepth = 0 , ctBaseType = 11 }
                           ]
                       })
              )
            , ( 1
              , Other
                  (NormalUInput
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
                       })
              )
            ]
          )
        , ( Other
              (NormalUInput
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
                   })
          , []
          )
        ]
  }