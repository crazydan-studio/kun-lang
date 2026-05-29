# 模式匹配聚焦：穷举、守卫、嵌套、解构

覆盖：变体模式、字面量模式、通配、List cons 模式、守卫子句、Tuple 解构、Record 解构、嵌套模式、类型收窄、穷举检查

```kun
-- ============================================================
-- pattern-matching.ku  —  模式匹配专题
-- 涵盖：变体 / 字面量 / 通配 / List cons / 守卫 / 解构 /
--      嵌套 / 类型收窄 / 穷举检查
-- ============================================================

-- ============================================================
-- ADT 定义
-- ============================================================

type Shape
  = Circle { radius : Float }
  | Rect { width : Float, height : Float }
  | Triangle { a : Float, b : Float, c : Float }

type Command
  = Run { program : Path, args : List<String> }
  | Pipe Command Command
  | Redirect { cmd : Command, file : Path, mode : RedirMode }

type RedirMode
  = Stdout
  | Stderr
  | Append

-- ============================================================
-- 1. 穷举匹配 + 通配
-- ============================================================

-- 无通配：必须覆盖所有变体
area : Shape -> Float
area = \shape ->
  case shape of
    Circle { radius }   -> 3.14159 * radius * radius
    Rect { width, height } -> width * height
    Triangle { a, b, c } -> -- Heron's formula
      let s = (a + b + c) / 2.0
      sqrt(s * (s - a) * (s - b) * (s - c))

-- 带通配：_ 覆盖未指定的变体
describe : Shape -> String
describe = \shape ->
  case shape of
    Circle _ -> "round"
    _        -> "angular"
-- Rect / Triangle 由通配覆盖

-- ============================================================
-- 2. 变体模式 + 变量绑定
-- ============================================================

describeResult : Result<Int, String> -> String
describeResult = \res ->
  case res of
    Ok 0    -> "zero"         -- 字面量 + 变体
    Ok n    -> f"got: {n}"
    Err msg -> f"error: {msg}"

-- Maybe 模式
head : List<a> -> Maybe<a>
head = \list ->
  case list of
    x :: _ -> Just(x)
    []     -> None

-- ============================================================
-- 3. List 模式（cons 解构）
-- ============================================================

-- 基本 cons
sum : List<Int> -> Int
sum = \list ->
  case list of
    []      -> 0
    x :: xs -> x + sum(xs)

-- 多元素前缀匹配
startsWithOneTwo : List<Int> -> Bool
startsWithOneTwo = \list ->
  case list of
    1 :: 2 :: rest -> true
    _              -> false

-- 长度判断
describeList : List<a> -> String
describeList = \list ->
  case list of
    []          -> "empty"
    _ :: []     -> "singleton"
    _ :: _ :: [] -> "pair"
    _           -> "longer"

-- ============================================================
-- 4. 守卫子句（when）
-- ============================================================

classify : Int -> String
classify = \n ->
  case n of
    0           -> "zero"
    m when m > 0 && m <= 10  -> "small positive"
    m when m > 10            -> "large positive"
    m when m < 0 && m >= -10 -> "small negative"
    _                        -> "large negative"

-- 守卫 + 变体模式
describeMaybe : Maybe<Int> -> String
describeMaybe = \m ->
  case m of
    Just n when n > 100 -> "big number"
    Just n when n < 0   -> "negative"
    Just _              -> "some value"
    None                -> "nothing"

-- ============================================================
-- 5. 元组解构
-- ============================================================

-- let 中的元组解构
swap : (a, b) -> (b, a)
swap = \pair ->
  let (x, y) = pair
  (y, x)

-- case 匹配元组内容
bothOrNothing : (Maybe<a>, Maybe<b>) -> Maybe<(a, b)>
bothOrNothing = \pair ->
  case pair of
    (Just a, Just b) -> Just((a, b))
    _                -> None

-- ============================================================
-- 6. Record 解构
-- ============================================================

type Point = { x : Float, y : Float }

-- let 中的 Record 解构
distance : Point -> Point -> Float
distance = \p1, p2 ->
  let { x = x1, y = y1 } = p1
  let { x = x2, y = y2 } = p2
  let dx = x2 - x1
  let dy = y2 - y1
  sqrt(dx * dx + dy * dy)

-- case 匹配 Record 内容
describePoint : Point -> String
describePoint = \p ->
  case p of
    { x = 0, y = 0 } -> "origin"
    { x = _, y = 0 } -> "on x axis"
    { x = 0, y = _ } -> "on y axis"
    _                -> "somewhere"

-- ============================================================
-- 7. 嵌套模式
-- ============================================================

-- 嵌套变体 + Record
describeCmd : Command -> String
describeCmd = \cmd ->
  case cmd of
    -- 嵌套匹配
    Run { program, args } ->
      f"run: {program}"

    -- 嵌套变体中的嵌套 Record
    Pipe (Run { program = p1, args = _ })
         (Run { program = p2 }) ->
      f"pipe: {p1} | {p2}"

    -- 多层嵌套
    Redirect { cmd = Pipe(_, _), file = f, mode = Append } ->
      f"append pipe output to {f}"

    -- 通配兜底
    _ -> "complex command"

-- 更深嵌套
type Expr
  = IntLit Int
  | Add Expr Expr
  | Mul Expr Expr

simplify : Expr -> Expr
simplify = \expr ->
  case expr of
    -- 0 + x = x
    Add(IntLit(0), x) -> simplify(x)
    -- x + 0 = x
    Add(x, IntLit(0)) -> simplify(x)
    -- 1 * x = x
    Mul(IntLit(1), x) -> simplify(x)
    -- 双层嵌套
    Add(IntLit(a), IntLit(b)) -> IntLit(a + b)
    -- 递归简化
    Add(x, y) -> Add(simplify(x), simplify(y))
    Mul(x, y) -> Mul(simplify(x), simplify(y))
    _         -> expr

-- ============================================================
-- 8. 字面量模式
-- ============================================================

-- Bool 字面量
negate : Bool -> Bool
negate = \b ->
  case b of
    true  -> false
    false -> true

-- Int 字面量
fizzbuzz : Int -> String
fizzbuzz = \n ->
  case n % 15 of
    0 -> "fizzbuzz"
    _ -> case n % 3 of
      0 -> "fizz"
      _ -> case n % 5 of
        0 -> "buzz"
        _ -> toString(n)

-- String 字面量
parseHttpStatus : String -> Int
parseHttpStatus = \status ->
  case status of
    "200" -> 200
    "201" -> 201
    "301" -> 301
    "404" -> 404
    "500" -> 500
    _     -> 0

-- ============================================================
-- 9. 类型收窄（Type Narrowing）
-- ============================================================

-- case 分支中变量类型自动收窄
processNode : Tree<Int> -> Int
processNode = \tree ->
  case tree of
    Leaf v          -> v                           -- v : Int
    Node(left, right) ->                           -- left, right : Tree<Int>
      processNode(left) + processNode(right)

-- ============================================================
-- 10. If 表达式与模式匹配对比
-- ============================================================

-- if 适合简单布尔判断
checkFile : Path -> String
checkFile = \p ->
  if p.exists() then "exists" else "not found"

-- case 适合多分支和结构解构（推荐）
checkFile' : Path -> String
checkFile' = \p ->
  case fileType(p) of
    Ok RegularFile   -> "regular file"
    Ok Directory     -> "directory"
    Ok Symlink       -> "symlink"
    Ok _             -> "other"
    Err _            -> "unknown"
```
