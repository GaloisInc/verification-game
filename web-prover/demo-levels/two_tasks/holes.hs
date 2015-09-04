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