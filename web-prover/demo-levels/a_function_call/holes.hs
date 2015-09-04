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