import Base: require

export @require

isprecompiling() = ccall(:jl_generating_output, Cint, ()) == 1

loaded(mod) = getthing(Main, mod) != nothing

const modlisteners = Dict{AbstractString,Vector{Function}}()

listenmod(f, mod) =
  loaded(mod) ? f() :
    modlisteners[mod] = push!(get(modlisteners, mod, Function[]), f)

loadmod(mod) =
  map(f->f(), get(modlisteners, mod, []))

importexpr(mod::Symbol) = Expr(:import, mod)
importexpr(mod::Expr) = Expr(:import, map(Symbol, split(string(mod), "."))...)

function withpath(f, path)
  tls = task_local_storage()
  hassource = haskey(tls, :SOURCE_PATH)
  hassource && (path′ = tls[:SOURCE_PATH])
  tls[:SOURCE_PATH] = path
  try
    return f()
  finally
    hassource ?
      (tls[:SOURCE_PATH] = path′) :
      delete!(tls, :SOURCE_PATH)
  end
end

function err(f, listener, mod)
  try
    f()
  catch e
    warn("Error requiring $mod from $listener:")
    showerror(STDERR, e, catch_backtrace())
    println(STDERR)
  end
end

macro require(mod, expr)
  ex = quote
    # Check if module can be found
    @static if Base.find_in_node_path($(String(mod)), nothing, 1) !== nothing
      using $mod
      $expr
    else
      const $mod = ccall(:jl_new_module, Any, (Any,), $(QuoteNode(mod)))
      ccall(:jl_module_optional, Void, (Any,), $mod)
    end
  end
  return (esc(ex))
end
