using DBI
using Compat
using PostgreSQL
using Base.Test

include("testutils.jl")
@testset "Main" begin
    include("connection.jl")
    # include("dbi_impl.jl")
    # include("data.jl")
    # include("postgres.jl")
    # include("dataframes_impl.jl")
end
