# 类型系统聚焦：类型定义与泛型

覆盖：ADT 全部变体字段风格、Newtype、泛型（空格分隔）、Let-多态、显式类型转换、Record 类型、函数类型（Elm 风格）

```
// ============================================================
// type-showcase.ku  —  类型系统聚焦
// 涵盖：ADT（无字段 / 无名字段 / 元组字段 / Record 字段）、
//       Newtype、泛型 ADT（空格分隔）、Let-多态、显式类型转换、
//       Record 类型、函数类型
// ============================================================

// ============================================================
// 1. ADT — 四种变体字段风格
// ============================================================

// 1a. 无字段（枚举风格）
type Color
  = Red
  | Green
  | Blue
  | Yellow

// 1b. 无名字段（空格分隔）
type FileError
  = NotFound Path
  | PermissionDenied Path
  | AlreadyExists Path

// 1c. 元组风格字段（圆括号，多值）
type IpAddress
  = Ipv4 (Nat, Nat, Nat, Nat)
  | Ipv6 (Nat, Nat, Nat, Nat, Nat, Nat, Nat, Nat)

// 1d. Record 风格字段（花括号，具名）
type HttpRequest
  = Get { url : String, headers : Map String String }
  | Post { url : String, body : String, headers : Map String String }

// 混合：同一类型可混合，但推荐统一风格
type Error
  = IoError IOError
  | NetworkError { host : String, port : Port }
  | Timeout Duration
  | Unknown

// ============================================================
// 2. Newtype — 单变体 ADT 的包装语义
// ============================================================

type UserName = UserName String
type UserId   = UserId Nat
type GroupId  = GroupId Nat
type Email    = Email String

// 构造器即函数
createUser : UserName -> UserId -> Email -> { name : UserName, uid : UserId, email : Email }
createUser = \name uid email ->
  { name  = name
  , uid   = uid
  , email = email
  }

// ============================================================
// 3. 泛型 ADT（空格分隔泛型参数）
// ============================================================

// 标准泛型：Maybe t 而非 Maybe<T>
type Maybe t
  = Just t
  | None

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
type Command t
  = Shell String
  | Function t
  | Pipeline (Command Any, Command t)

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

// IO 包装：IO Unit
greet : IO Unit
greet = print "hello"

// 高阶函数：(a -> b) -> List a -> List b
map : (a -> b) -> List a -> List b
map = \f list -> ...

// 函数返回 Record（类型别名在导入时指定，非函数类型不支持 type 定义）
createUserRecord : String -> Int -> String -> { name : String, age : Int, email : String }
createUserRecord = \name age email ->
  { name  = name
  , age   = age
  , email = email
  }

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
firstElem : Maybe Int
firstElem = identity (Just 42)

// ============================================================
// 6. 显式类型转换
// ============================================================

conversions : (Int, Nat, Float, String, Bytes)
conversions =
  let
    n  = 42           // Int
    u  = 42u          // Nat
    f  = 3.14         // Float

    // Nat <-> Int
    n1 = toInt u     // Nat -> Int（始终安全）
    u1 = toNat n     // Int -> Nat（负数 → Panic）

    // Float <-> Int
    f1 = toFloat n   // Int -> Float
    n2 = toInt f     // Float -> Int（截断）

    // String <-> Bytes
    b  = toBytes "hello"  // String -> Bytes
    s  = toString b       // Bytes -> String
  in
  (n1, u1, f1, b, s)

// ============================================================
// 7. 模式匹配中的类型收窄
// ============================================================

// 在 case 分支中，被绑定变量获得更精确的类型
processResult : Result Int String -> String
processResult = \res ->
  case res of
    Ok n  -> f"number: {n}"   // 此处 n : Int
    Err _ -> "error"           // 类型已知

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
// Maybe    : Type -> Type
// Result   : Type -> Type -> Type

// 完整应用归约到 Type：
// List Int       : Type
// Maybe String   : Type
// Result Int String : Type
```
