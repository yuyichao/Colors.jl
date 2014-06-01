# Support Data for color maps
include("maps_data.jl")

# Color Scale Generation
# ----------------------

# Generate n maximally distinguishable colors.
#
# This uses a greedy brute-force approach to choose n colors that are maximally
# distinguishable. Given seed color(s), and a set of possible hue, chroma, and
# lightness values (in LCHab space), it repeatedly chooses the next color as the
# one that maximizes the minimum pairwise distance to any of the colors already
# in the palette.
#
# Args:
#   n: Number of colors to generate.
#   seed: Initial color(s) included in the palette.
#   transform: Transform applied to colors before measuring distance.
#   lchoices: Possible lightness values.
#   cchoices: Possible chroma values.
#   hchoices: Possible hue values.
#
# Returns:
#   A Vector{ColorValue} of length n.
#
function distinguishable_colors{T<:ColorValue}(n::Integer,
                            seed::Vector{T};
                            transform::Function = identity,
                            lchoices::Vector{Float64} = linspace(0, 100, 15),
                            cchoices::Vector{Float64} = linspace(0, 100, 15),
                            hchoices::Vector{Float64} = linspace(0, 340, 20))
    if n <= length(seed)
        return seed[1:n]
    end

    # Candidate colors
    N = length(lchoices)*length(cchoices)*length(hchoices)
    candidate = Array(T, N)
    j = 0
    for h in hchoices, c in cchoices, l in lchoices
        candidate[j+=1] = LCHab(l, c, h)
    end

    # Transformed colors
    tc = transform(candidate[1])
    candidate_t = Array(typeof(tc), N)
    candidate_t[1] = tc
    for i = 2:N
        candidate_t[i] = transform(candidate[i])
    end

    # Start with the seed colors
    colors = Array(T, n)
    copy!(colors, seed)

    # Minimum distances of the current color to each previously selected color.
    ds = fill(Inf, N)
    for i = 1:length(seed)
        ts = transform(seed[i])
        for k = 1:N
            ds[k] = min(ds[k], colordiff(ts, candidate_t[k]))
        end
    end

    for i in length(seed)+1:n
        j = indmax(ds)
        colors[i] = candidate[j]
        tc = candidate_t[j]
        for k = 1:N
            d = colordiff(tc, candidate_t[k])
            ds[k] = min(ds[k], d)
        end
    end

    colors
end


distinguishable_colors(n::Integer, seed::ColorValue; kwargs...) = distinguishable_colors(n, [seed]; kwargs...)
distinguishable_colors(n::Integer; kwargs...) = distinguishable_colors(n, Array(RGB,0); kwargs...)

@deprecate distinguishable_colors(n::Integer,
                                transform::Function,
                                seed::ColorValue,
                                ls::Vector{Float64},
                                cs::Vector{Float64},
                                hs::Vector{Float64})    distinguishable_colors(n, [seed], transform = transform, lchoices = ls, cchoices = cs, hchoices = hs)


# Small definitions to make color computations more clear
+(x::LCHuv, y::LCHuv) = LCHuv(x.l+y.l,x.c+y.c,x.h+y.h)
*(x::Real, y::LCHuv) = LCHuv(x*y.l,x*y.c,x*y.h)

# Sequential palette
# ----------------------
# Sequential_palette implements the color palette creation technique by
# Wijffelaars, M., et al. (2008)
# http://magnaview.nl/documents/MagnaView-M_Wijffelaars-Generating_color_palettes_using_intuitive_parameters.pdf
#
# Colormaps are formed using Bezier curves in LCHuv colorspace
# with some constant hue. In addition, start and end points can be given
# that are then blended to the original hue smoothly.
#
# The arguments are:
# N        - number of colors
# h        - the main hue [0,360]
# c        - the overall lightness contrast [0,1]
# s        - saturation [0,1]
# b        - brightness [0,1]
# w        - cold/warm parameter, i.e. the strength of the starting color [0,1]
# d        - depth of the ending color [0,1]
# wcolor   - starting color (warmness)
# dcolor   - ending color (depth)
# logscale - true/false for toggling logspacing
#
function sequential_palette(h,
                            N::Int=100;
                            c=0.88,
                            s=0.6,
                            b=0.75,
                            w=0.15,
                            d=0.0,
                            wcolor=RGB(1,1,0),
                            dcolor=RGB(0,0,1),
                            logscale=false)

    function MixHue(a,h0,h1)
        M=mod(180.0+h1-h0, 360)-180.0
        mod(h0+a*M, 360)
    end

    pstart=convert(LCHuv, wcolor)
    p1=MSC(h)
    #p0=LCHuv(0,0,h) #original end point
    pend=convert(LCHuv, dcolor)

    #multi-hue start point
    p2l=100*(1.-w)+w*pstart.l
    p2h=MixHue(w,h,pstart.h)
    p2c=min(MSC(p2h,p2l), w*s*pstart.c)
    p2=LCHuv(p2l,p2c,p2h)

    #multi-hue ending point
    p0l=20.0*d
    p0h=MixHue(d,h,pend.h)
    p0c=min(MSC(p0h,p0l), d*s*pend.c)
    p0=LCHuv(p0l,p0c,p0h)

    q0=(1.0-s)*p0+s*p1
    q2=(1.0-s)*p2+s*p1
    q1=0.5*(q0+q2)

    pal = RGB[]

    if logscale
        absc = logspace(-2.,0.,N)
    else
        absc = linspace(0.,1.,N)
    end

    for t in absc
        u=1.0-t

        #Change grid to favor light colors and to be uniform along the curve
        u = (125.0-125.0*0.2^((1.0-c)*b+u*c))
        u = invBezier(u,p0.l,p2.l,q0.l,q1.l,q2.l)

        #Get color components from Bezier curves
        ll = Bezier(u, p0.l, p2.l, q0.l, q1.l, q2.l)
        cc = Bezier(u, p0.c, p2.c, q0.c, q1.c, q2.c)
        hh = Bezier(u, p0.h, p2.h, q0.h, q1.h, q2.h)

        push!(pal, convert(RGB, LCHuv(ll,cc,hh)))
    end

    pal
end


# Diverging palettes
# ----------------------
# Create diverging palettes by combining 2 sequential palettes
#
# The arguments are:
# N        - number of colors
# h1       - the main hue of the left side [0,360]
# h2       - the main hue of the right side [0,360]
# c        - the overall lightness contrast [0,1]
# s        - saturation [0,1]
# b        - brightness [0,1]
# w        - cold/warm parameter, i.e. the strength of the starting color [0,1]
# d1       - depth of the ending color in the left side [0,1]
# d2       - depth of the ending color in the right side [0,1]
# wcolor   - starting color (warmness)
# dcolor1  - ending color of the left side (depth)
# dcolor2  - ending color of the right side (depth)
# logscale - true/false for toggling logspacing
#
function diverging_palette(h1,
                           h2,
                           N::Int=100;
                           mid=0.5,
                           c=0.88,
                           s=0.6,
                           b=0.75,
                           w=0.15,
                           d1=0.0,
                           d2=0.0,
                           wcolor=RGB(1,1,0),
                           dcolor1=RGB(1,0,0),
                           dcolor2=RGB(0,0,1),
                           logscale=false)

    if isodd(N)
        n=N-1
    else
        n=N
    end
    N1 = int(max(ceil(mid*n), 1))
    N2 = int(max(n-N1, 1))

    pal1 = sequential_palette(h1, N1+1, w=w, d=d1, c=c, s=s, b=b, wcolor=wcolor, dcolor=dcolor1, logscale=logscale)
    pal1 = flipud(pal1)

    pal2 = sequential_palette(h2, N2+1, w=w, d=d2, c=c, s=s, b=b, wcolor=wcolor, dcolor=dcolor2, logscale=logscale)

    if isodd(N)
        midcol = weighted_color_mean(0.5, pal1[end], pal2[1])
        return [pal1[1:end-1], midcol, pal2[2:end]]
    else
        return [pal1[1:end-1], pal2[2:end]]
    end
end


# Colormap
# ----------------------
# Main function to handle different predefined colormaps
#
function colormap(cname::String, N::Int=100; mid=0.5, logscale=false, kvs...)

    cname = lowercase(cname)
    if haskey(colormaps_sequential, cname)
        vals = colormaps_sequential[cname]

        p=Array(Any,8)
        for i in 1:8
            p[i] = vals[i]
        end

        for (k,v) in kvs
            ind = findfirst([:h, :w, :d, :c, :s, :b, :wcolor, :dcolor], k)
            if ind > 0
                p[ind] = v
            end
        end

        return sequential_palette(p[1], N, w=p[2], d=p[3], c=p[4], s=p[5], b=p[6], wcolor=p[7], dcolor=p[8], logscale=logscale)

    elseif haskey(colormaps_diverging, cname)
        vals = colormaps_diverging[cname]

        p=Array(Any,11)
        for i in 1:11
            p[i] = vals[i]
        end

        for (k,v) in kvs
            ind = findfirst([:h, :h2, :w, :d1, :d2, :c, :s, :b, :wcolor, :dcolor1, :dcolor2], k)
            if ind > 0
                p[ind] = v
            end
        end

        return diverging_palette(p[1], p[2], N, w=p[3], d1=p[4], d2=p[5], c=p[6], s=p[7], b=p[8], wcolor=p[9], dcolor1=p[10], dcolor2=p[11], mid=mid, logscale=logscale)

    else
        error("Unknown colormap: ", cname)
    end

end
