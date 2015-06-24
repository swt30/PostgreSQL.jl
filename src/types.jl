import DataArrays: NAtype

abstract AbstractPostgresType
type PostgresType{Name} <: AbstractPostgresType end

abstract AbstractOID
type OID{N} <: AbstractOID end

oid{T<:AbstractPostgresType}(t::Type{T}) = convert(OID, t)
pgtype(t::Type) = convert(PostgresType, t)

Base.convert{T}(::Type{Oid}, ::Type{OID{T}}) = convert(Oid, T)

#=macro pgtype(pgtypename, oid)
    quote
        $(esc(:(Base.convert)))(::Type{OID}, ::Type{PostgresType{$pgtypename}}) = OID{$oid}
        $(esc(:(Base.convert)))(::Type{PostgresType}, ::Type{OID{$oid}}) = PostgresType{$pgtypename}
    end
end=#

function newpgtype(pgtypename, oid, jltypes)
    Base.convert(::Type{OID}, ::Type{PostgresType{pgtypename}}) = OID{oid}
    Base.convert(::Type{PostgresType}, ::Type{OID{oid}}) = PostgresType{pgtypename}

    for t in jltypes
        Base.convert(::Type{PostgresType}, ::Type{t}) = PostgresType{pgtypename}
    end
end

# macro pgtypeproxy(jltype, jltypeproxy)
#     $(esc(:pgdata))(ptr::Ptr{Uint8}, data::$jltype) = pgdata(ptr, convert($jltypeproxy, data))
# end


# @pgtype PostgresBool 16
# @pgtype PostgresByteArray 17
# @pgtype PostgresInt64 20
# @pgtype PostgresInt32 23
# @pgtype PostgresInt16 21
# @pgtype PostgresFloat64 701
# @pgtype PostgresFloat32 700
# @pgtype PostgresBlankPaddedChar 1042
# @pgtype PostgresVarChar 1043
# @pgtype PostgresUnknown 705

#=@pgtype :bool 16
@pgtype :bytea 17
@pgtype :int8 20
@pgtype :int4 23
@pgtype :int2 21
@pgtype :float8 701
@pgtype :float4 700
@pgtype :bpchar 1042
@pgtype :varchar 1043
@pgtype :text 25
@pgtype :unknown 705=#

newpgtype(:bool, 16, (Bool,))
newpgtype(:bytea, 17, (Vector{Uint8},))
newpgtype(:int8, 20, (Int64,))
newpgtype(:int4, 23, (Int32,))
newpgtype(:int2, 21, (Int16,))
newpgtype(:float8, 701, (Float64,))
newpgtype(:float4, 700, (Float32,))
newpgtype(:bpchar, 1042, ())
newpgtype(:varchar, 1043, (ASCIIString,UTF8String))
newpgtype(:text, 25, ())
newpgtype(:numeric, 1700, ())
newpgtype(:date, 1082, ())
newpgtype(:unknown, 705, (UnionType,NAtype))

typealias PGStringTypes Union(Type{PostgresType{:bpchar}},
                              Type{PostgresType{:varchar}},
                              Type{PostgresType{:text}},
                              Type{PostgresType{:date}})

function storestring!(ptr::Ptr{Uint8}, str::String)
    ptr = convert(Ptr{Uint8}, c_realloc(ptr, sizeof(str)+1))
    unsafe_copy!(ptr, convert(Ptr{Uint8}, str), sizeof(str)+1)
    return ptr
end

# In text mode, pq returns bytea as a text string "\xAABBCCDD...", for instance
# Uint8[0x01, 0x23, 0x45] would come in as "\x012345"
function decode_bytea_hex(s::String)
    if length(s) < 2 || s[1] != '\\' || s[2] != 'x'
        error("Malformed bytea string: $s")
    end
    return hex2bytes(s[3:end])
end

jldata(::Type{PostgresType{:date}}, ptr::Ptr{Uint8}) = bytestring(ptr)

jldata(::Type{PostgresType{:bool}}, ptr::Ptr{Uint8}) = bytestring(ptr) != "f"

jldata(::Type{PostgresType{:int8}}, ptr::Ptr{Uint8}) = parseint(Int64, bytestring(ptr))

jldata(::Type{PostgresType{:int4}}, ptr::Ptr{Uint8}) = parseint(Int32, bytestring(ptr))

jldata(::Type{PostgresType{:int2}}, ptr::Ptr{Uint8}) = parseint(Int16, bytestring(ptr))

jldata(::Type{PostgresType{:float8}}, ptr::Ptr{Uint8}) = parsefloat(Float64, bytestring(ptr))

jldata(::Type{PostgresType{:float4}}, ptr::Ptr{Uint8}) = parsefloat(Float32, bytestring(ptr))

function jldata(::Type{PostgresType{:numeric}}, ptr::Ptr{Uint8})
    s = bytestring(ptr)
    return search(s, '.') == 0 ? BigInt(s) : BigFloat(s)
end

jldata(::PGStringTypes, ptr::Ptr{Uint8}) = bytestring(ptr)

jldata(::Type{PostgresType{:bytea}}, ptr::Ptr{Uint8}) = bytestring(ptr) |> decode_bytea_hex

jldata(::Type{PostgresType{:unknown}}, ptr::Ptr{Uint8}) = None

function pgdata(::Type{PostgresType{:bool}}, ptr::Ptr{Uint8}, data::Bool)
    ptr = data ? storestring!(ptr, "TRUE") : storestring!(ptr, "FALSE")
end

function pgdata(::Type{PostgresType{:int8}}, ptr::Ptr{Uint8}, data::Number)
    ptr = storestring!(ptr, string(convert(Int64, data)))
end

function pgdata(::Type{PostgresType{:int4}}, ptr::Ptr{Uint8}, data::Number)
    ptr = storestring!(ptr, string(convert(Int32, data)))
end

function pgdata(::Type{PostgresType{:int2}}, ptr::Ptr{Uint8}, data::Number)
    ptr = storestring!(ptr, string(convert(Int16, data)))
end

function pgdata(::Type{PostgresType{:float8}}, ptr::Ptr{Uint8}, data::Number)
    ptr = storestring!(ptr, string(convert(Float64, data)))
end

function pgdata(::Type{PostgresType{:float4}}, ptr::Ptr{Uint8}, data::Number)
    ptr = storestring!(ptr, string(convert(Float32, data)))
end

function pgdata(::Type{PostgresType{:numeric}}, ptr::Ptr{Uint8}, data::Number)
    ptr = storestring!(ptr, string(data))
end

function pgdata(::PGStringTypes, ptr::Ptr{Uint8}, data::ByteString)
    ptr = storestring!(ptr, data)
end

function pgdata(::PGStringTypes, ptr::Ptr{Uint8}, data::String)
    ptr = storestring!(ptr, bytestring(data))
end

function pgdata(::PostgresType{:date}, ptr::Ptr{Uint8}, data::String)
    ptr = storestring!(ptr, bytestring(data))
    ptr = Dates.DateFormat(ptr)
end

function pgdata(::Type{PostgresType{:bytea}}, ptr::Ptr{Uint8}, data::Vector{Uint8})
    ptr = storestring!(ptr, bytestring("\\x", bytes2hex(data)))
end

# @pgtypeproxy Uint8 Int16
# @pgtypeproxy Uint16 Int32
# @pgtypeproxy Uint32 Int64

# dbi
abstract Postgres <: DBI.DatabaseSystem

type PostgresDatabaseHandle <: DBI.DatabaseHandle
    ptr::Ptr{PGconn}
    status::ConnStatusType
    closed::Bool

    function PostgresDatabaseHandle(ptr::Ptr{PGconn}, status::ConnStatusType)
        new(ptr, status, false)
    end
end

type PostgresResultHandle
    ptr::Ptr{PGresult}
    types::Vector{DataType}
    nrows::Integer
    ncols::Integer
end

function PostgresResultHandle(result::Ptr{PGresult})
    status = PQresultStatus(result)
    if status == PGRES_TUPLES_OK || status == PGRES_SINGLE_TUPLE
        oids = [OID{int(PQftype(result, col))} for col in 0:(PQnfields(result)-1)]
        types = DataType[convert(PostgresType, x) for x in oids]
    else
        types = DataType[]
    end
    return PostgresResultHandle(result, types, PQntuples(result), PQnfields(result))
end

type PostgresStatementHandle <: DBI.StatementHandle
    db::PostgresDatabaseHandle
    stmt::String
    executed::Int
    paramtypes::Array{DataType}
    finished::Bool
    result::PostgresResultHandle

    function PostgresStatementHandle(db::PostgresDatabaseHandle, stmt::String, executed=0, paramtypes::Array{DataType}=DataType[])
        new(db, stmt, executed, paramtypes, false)
    end
end

function Base.copy(rh::PostgresResultHandle)
    PostgresResultHandle(PQcopyResult(result, PG_COPYRES_ATTRS | PG_COPYRES_TUPLES |
        PG_COPYRES_NOTICEHOOKS | PG_COPYRES_EVENTS), copy(rh.types), rh.ntuples, rh.nfields)
end

