LevelPreds
  { lpredPre =
      NameT
        { nameTName = "p_galois'find'P"
        , nameTParams =
            [ TyCon "map" [ TyCon "int" [] , TyCon "int" [] ]
            , TyCon "map" [ TyCon "addr" [] , TyCon "addr" [] ]
            , TyCon "map" [ TyCon "addr" [] , TyCon "int" [] ]
            , TyCon "map" [ TyCon "addr" [] , TyCon "int" [] ]
            , TyCon "addr" []
            , TyCon "int" []
            , TyCon "int" []
            ]
        , nameTCTypes =
            [ CType { ctPtrDepth = 1 , ctBaseType = 7 }
            , CType { ctPtrDepth = 0 , ctBaseType = 7 }
            , CType { ctPtrDepth = 0 , ctBaseType = 7 }
            ]
        }
  , lpredLoops =
      [ NameT
          { nameTName = "p_galois'find'I1"
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
              , TyCon "int" []
              , TyCon "int" []
              , TyCon "addr" []
              , TyCon "int" []
              , TyCon "int" []
              ]
          , nameTCTypes =
              [ CType { ctPtrDepth = 1 , ctBaseType = 7 }
              , CType { ctPtrDepth = 0 , ctBaseType = 7 }
              , CType { ctPtrDepth = 0 , ctBaseType = 7 }
              , CType { ctPtrDepth = 0 , ctBaseType = 7 }
              , CType { ctPtrDepth = 0 , ctBaseType = 7 }
              , CType { ctPtrDepth = 1 , ctBaseType = 7 }
              , CType { ctPtrDepth = 0 , ctBaseType = 7 }
              , CType { ctPtrDepth = 0 , ctBaseType = 7 }
              ]
          }
      ]
  , lpredPost =
      NameT
        { nameTName = "p_galois'find'Q"
        , nameTParams =
            [ TyCon "map" [ TyCon "int" [] , TyCon "int" [] ]
            , TyCon "map" [ TyCon "addr" [] , TyCon "addr" [] ]
            , TyCon "map" [ TyCon "addr" [] , TyCon "int" [] ]
            , TyCon "map" [ TyCon "addr" [] , TyCon "int" [] ]
            , TyCon "map" [ TyCon "int" [] , TyCon "int" [] ]
            , TyCon "map" [ TyCon "addr" [] , TyCon "addr" [] ]
            , TyCon "map" [ TyCon "addr" [] , TyCon "int" [] ]
            , TyCon "map" [ TyCon "addr" [] , TyCon "int" [] ]
            , TyCon "int" []
            , TyCon "addr" []
            , TyCon "int" []
            , TyCon "int" []
            ]
        , nameTCTypes =
            [ CType { ctPtrDepth = 0 , ctBaseType = 7 }
            , CType { ctPtrDepth = 1 , ctBaseType = 7 }
            , CType { ctPtrDepth = 0 , ctBaseType = 7 }
            , CType { ctPtrDepth = 0 , ctBaseType = 7 }
            ]
        }
  , lpredCalls = fromList []
  }