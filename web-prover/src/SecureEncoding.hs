
module SecureEncoding where

import Serial
import Utils

import Control.Exception
import Control.Monad
import Crypto.Cipher.AES
import Crypto.Cipher.Types (AuthTag(AuthTag))
import Data.ByteString.Base64.Lazy as Base64
import Data.Text.Lazy (Text)
import System.IO
import System.IO.Error
import qualified Codec.Compression.Zlib as Zlib
import qualified Data.ByteString as BS
import qualified Data.ByteString.Lazy as LBS
import qualified Data.Text.Lazy.Encoding as Text

encapValue :: Serial a => SecurityContext -> a -> IO Text
encapValue secCxt snap =

  do iv <- randomBytes ivLength

     let aad = mempty -- additional authenticated data

         combineCipherTextAndTag (cipherText, AuthTag authTag) =
           LBS.fromChunks [iv, authTag, cipherText]
           -- The authtag is always 16 bytes

         encap = Text.decodeUtf8 -- ASCII is a subset of UTF-8
               . Base64.encode   -- make binary suitable for JSON
               . combineCipherTextAndTag
               . encryptGCM (secKey secCxt) iv aad
                                 -- GCM provides confidentiality and integrity
               . LBS.toStrict
               . Zlib.compress   -- lots of repetition in encoded format
               . Serial.encode

     return (encap snap)

-- 96-bit / 12-byte IVs are the recommended random length
ivLength :: Int
ivLength = 12

keyLength :: Int
keyLength = 16

-- GCM Auth Tag length is the cipher blocksize, 128-bit / 16-byte
authTagLength :: Int
authTagLength = 16

unencapValue :: Serial a => SecurityContext -> Text -> Maybe a
unencapValue secCxt encodedSnap =

  do let textToBytes = Base64.decode . Text.encodeUtf8
     rawBytes <- option (textToBytes encodedSnap)

     -- Extract iv, authTag, cipherText. Decrypt cipherText and verify authTag
     let (iv     , rawBytes1 ) = LBS.splitAt (fromIntegral ivLength     ) rawBytes
         (authTag, cipherText) = LBS.splitAt (fromIntegral authTagLength) rawBytes1
         aad                   = mempty

         decodeCompressed = Serial.decode
                          . Zlib.decompress
                          . LBS.fromStrict

         cipherToCompressed = decryptGCM (secKey secCxt) (LBS.toStrict iv) aad

         (plainText, AuthTag computedAuthTag)
            = cipherToCompressed (LBS.toStrict cipherText)

     guard (authTag == LBS.fromStrict computedAuthTag)

     decodeCompressed plainText


randomDevice :: FilePath
randomDevice = "/dev/urandom"

randomBytes :: Int -> IO BS.ByteString
randomBytes n = withFile randomDevice ReadMode (\h -> BS.hGet h n)

data SecurityContext = SecurityContext
  { secKey :: AES
  }

keyFile :: FilePath
keyFile = "snapshot_key.dat"

getSecurityContext :: IO SecurityContext
getSecurityContext =

  do let catchNotFound m n =
           catchJust (\e -> if isDoesNotExistError e then Just () else Nothing)
                     m
                     (const n)

     rawKey <- BS.readFile keyFile
               `catchNotFound`
               do key <- randomBytes keyLength
                  BS.writeFile keyFile key
                  return key

     return (SecurityContext (initAES rawKey))

