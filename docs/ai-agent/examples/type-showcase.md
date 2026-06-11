# 类型系统聚焦：类型定义与泛型

覆盖：ADT 全部变体字段风格、Newtype、泛型（空格分隔）、Let-多态、显式类型转换、Record 类型、函数类型（Elm 风格）

```kun
// ============================================================
// type-showcase.kun  —  类型系统聚焦
// 涵盖：ADT（无字段 / 无名字段 / 元组字段 / Record 字段）、
//       Newtype、泛型 ADT（空格分隔）、Let-多态、显式类型转换、
//       Record 类型、函数类型
// ============================================================

// ============================================================
// 1. ADT 定义与和类型
// ============================================================

// 简单 ADT（无字段变体）
type Color
  = Red
  | Green
  | Blue

// Newtype（单变体）：包装已有类型为新类型
type UserId
  = UserId Int
type GroupId
  = GroupId Int
type Email
  = Email String

// 构造器即函数
createUser : String -> UserId -> Email -> { name : String, uid : UserId, email : Email }
createUser = \name uid email ->
  { name  = name
  , uid   = uid
  , email = email
  }

// ============================================================
// 2. ADT 全部变体字段风格
// ============================================================

// Newtype（单变体）与 `of` 构造器
type ExitCode = ExitCode Int
success         = ExitCode.of 0
generalError    = ExitCode.of 1
commandNotFound = ExitCode.of 127

// 无名字段变体（空格分隔）
type ProcessError
  = ParseFailed String
  | FileNotFound Path

// 元组字段变体
type IpAddress
  = Ipv4 (Int, Int, Int, Int)
  | Ipv6 (Int, Int, Int, Int, Int, Int, Int, Int)

// Record 字段变体
type Shape
  = Circle { radius : Float }
  | Rect { width : Float, height : Float }
  | Triangle { a : Float, b : Float, c : Float }

// ============================================================
// 3. 泛型 ADT（空格分隔泛型参数）
// ============================================================

// Nilable 类型为语言内置（?T），非 ADT
// 多参数：Result t e 而非 Result<T, E>
type Result t e
  = Ok t
  | Err e

// 多参数泛型
type Pair a b
  = Pair a b

type Either l r
  = Left l
  | Right r

// 递归泛型 ADT
type JsonValue
  = JsonNull
  | JsonBool Bool
  | JsonInt Int
  | JsonFloat Float
  | JsonString String
  | JsonArray (List JsonValue)
  | JsonObject (Map String JsonValue)

// 嵌套泛型
type Tree t
  = Leaf t
  | Node (Tree t, Tree t)

// ============================================================
// 4. 类型标注与函数类型（Elm 风格）
// ============================================================

// 纯函数：Int -> Int
double : Int -> Int
double = \x -> x * 2

// 柯里化函数：Int -> Int -> Int
add : Int -> Int -> Int
add = \x y -> x + y

// 元组参数：(Int, Int) -> Int
addPair : (Int, Int) -> Int
addPair = \(x, y) -> x + y

// 高阶函数：(a -> b) -> List a -> List b
map : (a -> b) -> List a -> List b
map = \f list -> ...

// 函数返回 Record
createUserRecord : String -> Int -> String -> { name : String, age : Int, email : String }
createUserRecord = \name age email ->
  { name  = name
  , age   = age
  , email = email
  }

// 零参函数（仅 IO 效应）
now : -> DateTime
now = \ ->
  do
    Sys.time

// ============================================================
// 5. Let-多态（Hindley-Milner 自动泛型）
// ============================================================

// identity 自动获得泛型类型
identity = \x -> x
// identity : a -> a

// 每次使用可实例化为不同类型
n : Int
n = identity 42

s : String
s = identity "hello"

b : Bool
b = identity true

// 复合类型实例化
firstElem : Int
firstElem = identity 42

// ============================================================
// 6. 显式类型转换
// ============================================================

conversions : (Int, Float, String, Bytes)
conversions =
  let
    n  = 42       // Int
    f  = 3.14     // Float

    // Float <-> Int
    f1 = toFloat n        // Int -> Float
    n2 = toInt f          // Float -> Int（截断）

    // String <-> Bytes
    b  = toBytes "hello"   // String -> Bytes
    s  = toString b        // Bytes -> String
  in
    (n2, f1, b, s)

// ============================================================
// 7. 模式匹配中的类型收窄
// ============================================================

// 在 case 分支中，被绑定变量获得更精确的类型
processResult : Result Int String -> String
processResult = \res ->
  case res of
    Ok n  -> f"number: {n}"      // 此处 n : Int
    Err _ -> "error"             // 类型已知

processIp : IpAddress -> String
processIp = \addr ->
  case addr of
    Ipv4 (a, b, c, d) ->
      f"{a}.{b}.{c}.{d}"
    Ipv6 (a, b, c, d, e, f, g, h) ->
      "ipv6"

// ============================================================
// 8. 种类（Kind）隐式示例
// ============================================================

// Type 种类：值可居留
x : Int          // Int : Type
y : Bool         // Bool : Type
z : String       // String : Type

// Type -> Type 种类：类型构造器
// List     : Type -> Type
// Result   : Type -> Type -> Type
// Set      : Type -> Type

// 完整应用归约到 Type：
// List Int       : Type
// ?String        : Type（Nilable 是语言内置）
// Result Int String : Type
```
