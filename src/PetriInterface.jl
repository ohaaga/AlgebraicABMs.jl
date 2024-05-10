"""
Petri nets as a presentation of certain kinds of rewrite rules.
"""
module PetriInterface

using AlgebraicRewriting, Catlab, AlgebraicPetri
using Fleck
using Random
import AlgebraicRewriting.Incremental: IncSumHomSet

using ..RewriteSemiMarkov: ClockSystem, ClockKeyType, sampl, rng
import ..RewriteSemiMarkov: run!

"""Give a name for a Petri Net transition (name = label)"""
ob_name(pn::LabelledPetriNet, s::Int)::Symbol = pn[s, :sname]

"""Give a name for a Petri Net transition (e.g. name = "S3" for species #3)"""
ob_name(::PetriNet, s::Int)::Symbol = Symbol("S$s")

"""
Creates a discrete C-Set from a Petri net with one object for each species in
the Petri net. By default, this creates an *empty* C-Set instance, but there 
are two ways one may also wish to specify how many tokens are in each species.
One can give a vector, where the indices correspond to the indices of the S
table of the petri net. Alternatively, one can give keyword arguments where 
the keys are the names of the species (as determined by `ob_name`). 

For example, `PetriNetCSet(sir_labeled_pn, S=20, I=1)` would create an *instance* 
of a C-Set that has three tables ("S","I","R"), no morphisms nor attributes, 
and that instance would have 20 rows in the "S" table and 1 row in the "I"
table. In general, instances on this schema are effectively named tuples 
(S::Int,I::Int,R::Int).
"""
function PetriNetCSet(pn::AbstractPetriNet, args=[]; kw...)
  res = AnonACSet(BasicSchema(ob_name.(Ref(pn), parts(pn, :S)),[]))
  for (arg, s) in zip(args, parts(pn, :S))
    add_parts!(res, ob_name(pn, s), arg)  # Add tokens from Vector{Int}
  end
  for (s, arg) in pairs(kw)
    add_parts!(res, s, arg)  # Add tokens by name
  end
  res
end

"""Assumes that tokens are deleted and recreated, rather than preserved"""
function make_rule(pn::Union{PetriNet, LabelledPetriNet}, t::Int)
  L, R = LR = [PetriNetCSet(pn) for _ in 1:2]
  add_part!.(Ref(L), ob_name.(Ref(pn), pn[incident(pn, t, :it), :is]))
  add_part!.(Ref(R), ob_name.(Ref(pn), pn[incident(pn, t, :ot), :os]))
  Rule(create.(LR)...)
end

make_rules(pn) = make_rule.(Ref(pn), parts(pn, :T))

"""
Convert a Petri net into a `ClockSystem`, given a dictionary of timers 
(corresponding to the transitions) as well as an initial state (such that the 
incremental hom-sets can be initialized). The schema for `init` is expected to 
be the `MarkedLabelledPetriNet` schema if `spn::T` is itself a 
`MarkedLabelledPetriNet`, but if `spn` is an unmarked Petri Net then it is 
assumed `init` will be the schema generated by `PetriNetCSet` above.

The result can be used with `run!(::ClockSystem, ::ACSet)` where the second
parameter should be the same `init` ACSet used to generate the `ClockSystem`.
"""
function to_clocksys(spn::AbstractPetriNet, init::ACSet, clockdists)  
  clock = @acset ClockSystem begin
    Global=1
    rng=[Random.RandomDevice()]
    sampler=[FirstToFire{ClockKeyType, Float64}()] # Fleck sampler
    Event=nt(spn)
    name=spn[:,:tname]
  end

  # add rules, distributions
  for t in parts(clock,:Event)
    clock[t,:rule] = make_rule(spn, t)
    clock[t,:dist] = clockdists[clock[t,:name]]    
  end

  # make incremental homsets after all rules are made
  for t in parts(clock, :Event)
    clock[t,:match] = IncSumHomSet(IncHomSet(codom(left(clock[t,:rule])),  
                                             right.(clock[:,:rule]), init))
  end

  # which rules are always enabled?
  aa = [t for t in parts(spn, :T) if isempty(incident(spn, t, :it))]
  add_parts!(clock, :AlwaysEnabled, length(aa); always_enabled=aa)

  for t in parts(clock,:Event)
    newkeys = [(t,k) for k in keys(clock[t,:match])]
    add_parts!(
      clock, :Clock, length(newkeys);
      key = newkeys, event = fill(t, length(newkeys))
    )
    for c in newkeys
      enable!(sampl(clock), c, clock[t, :dist](0.), 0., 0., rng(clock))
    end
  end
  
  return clock
end 

function run!(mlpn::T, clockdists, init::ACSet; kw...) where {T<:AbstractPetriNet}
  run!(to_clocksys(mlpn, init, clockdists), init; kw...)
end


end # module