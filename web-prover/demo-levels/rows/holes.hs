LevelPreds
  { lpredPre =
      NameT
        { nameTName = "p_galois'rows'P"
        , nameTParams =
            [ TyCon "map" [ TyCon "int" [] , TyCon "int" [] ]
            , TyCon "map" [ TyCon "addr" [] , TyCon "addr" [] ]
            , TyCon "map" [ TyCon "addr" [] , TyCon "int" [] ]
            , TyCon "map" [ TyCon "addr" [] , TyCon "int" [] ]
            , TyCon "addr" []
            , TyCon "int" []
            ]
        , nameTCTypes =
            [ CType { ctPtrDepth = 1 , ctBaseType = 3 }
            , CType { ctPtrDepth = 0 , ctBaseType = 11 }
            ]
        }
  , lpredLoops =
      [ NameT
          { nameTName = "p_galois'rows'I1"
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
              , TyCon "addr" []
              , TyCon "int" []
              ]
          , nameTCTypes =
              [ CType { ctPtrDepth = 1 , ctBaseType = 3 }
              , CType { ctPtrDepth = 0 , ctBaseType = 11 }
              , CType { ctPtrDepth = 0 , ctBaseType = 11 }
              , CType { ctPtrDepth = 0 , ctBaseType = 11 }
              , CType { ctPtrDepth = 1 , ctBaseType = 3 }
              , CType { ctPtrDepth = 0 , ctBaseType = 11 }
              ]
          }
      , NameT
          { nameTName = "p_galois'rows'I2"
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
              , TyCon "addr" []
              , TyCon "int" []
              ]
          , nameTCTypes =
              [ CType { ctPtrDepth = 1 , ctBaseType = 3 }
              , CType { ctPtrDepth = 0 , ctBaseType = 11 }
              , CType { ctPtrDepth = 0 , ctBaseType = 11 }
              , CType { ctPtrDepth = 0 , ctBaseType = 11 }
              , CType { ctPtrDepth = 1 , ctBaseType = 3 }
              , CType { ctPtrDepth = 0 , ctBaseType = 11 }
              ]
          }
      ]
  , lpredPost =
      NameT
        { nameTName = "p_galois'rows'Q"
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
            [ CType { ctPtrDepth = 1 , ctBaseType = 3 }
            , CType { ctPtrDepth = 0 , ctBaseType = 11 }
            ]
        }
  , lpredCalls = fromList []
  }