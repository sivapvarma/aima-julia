
export AbstractPDDL,
        PDDL, goal_test, execute_action,
        AbstractPlanningAction, PlanningAction,
        substitute, check_precondition,
        air_cargo_pddl, air_cargo_goal_test,
        spare_tire_pddl, spare_tire_goal_test,
        three_block_tower_pddl, three_block_tower_goal_test,
        have_cake_and_eat_cake_too_pddl, have_cake_and_eat_cake_too_goal_test;

abstract AbstractPDDL;

abstract AbstractPlanningAction;

#=

    PlanningAction is an action schema defined by the action's name, preconditions, and effects.

    Preconditions and effects consists of either positive and negated literals.

=#
type PlanningAction <: AbstractPlanningAction
    name::String
    arguments::Tuple
    precondition_positive::Array{Expression, 1}
    precondition_negated::Array{Expression, 1}
    effect_add_list::Array{Expression, 1}
    effect_delete_list::Array{Expression, 1}

    function PlanningAction(action::Expression, precondition::Tuple{Vararg{Array{Expression, 1}, 2}}, effect::Tuple{Vararg{Array{Expression, 1}, 2}})
        return new(action.operator, action.arguments, precondition[1], precondition[2], effect[1], effect[2]);
    end
end

function substitute{T <: AbstractPlanningAction}(action::T, e::Expression, arguments::Tuple{Vararg{Expression}})
    local new_arguments::AbstractVector = collect(e.arguments);
    for (index_1, argument) in enumerate(e.arguments)
        for index_2 in 1:length(action.arguments)
            if (action.arguments[index_2] == argument)
                new_arguments[index_1] = arguments[index_2];
            end
        end
    end
    return Expression(e.operator, Tuple((new_arguments...)));
end

function check_precondition{T1 <: AbstractPlanningAction, T2 <: AbstractKnowledgeBase}(action::T1, kb::T2, arguments::Tuple)
    # Check for positive clauses.
    for clause in action.precondition_positive
        if (!(substitute(action, clause, arguments) in kb.clauses))
            return false;
        end
    end
    # Check for negated clauses.
    for clause in action.precondition_negated
        if (substitute(action, clause, arguments) in kb.clauses)
            return false;
        end
    end
    return true;
end

function execute_action{T1 <: AbstractPlanningAction, T2 <: AbstractKnowledgeBase}(action::T1, kb::T2, arguments::Tuple)
    if (!(check_precondition(action, kb, arguments)))
        error(@sprintf("execute_action(): Action \"%s\" preconditions are not satisfied!", action.name));
    end
    # Retract negated literals to knowledge base 'kb'.
    for clause in action.effect_delete_list
        retract(kb, substitute(action, clause, arguments));
    end
    # Add positive literals to knowledge base 'kb'.
    for clause in action.effect_add_list
        tell(kb, substitute(action, clause, arguments));
    end
    nothing;
end

#=

    The Planning Domain Definition Language (PDDL) is used to define a search problem.

    The states (starting from the initial state) are represented as the conjunction of

    the statements in 'kb' (a FirstOrderLogicKnowledgeBase). The actions are described

    by 'actions' (an array of action schemas). The 'goal_test' is a function that checks

    if the current state of the problem is at the goal state.

=#
type PDDL <: AbstractPDDL
    kb::FirstOrderLogicKnowledgeBase
    actions::Array{PlanningAction, 1}
    goal_test::Function

    function PDDL(initial_state::Array{Expression, 1}, actions::Array{PlanningAction, 1}, goal_test::Function)
        return new(FirstOrderLogicKnowledgeBase(initial_state), actions, goal_test);
    end
end

function goal_test{T <: AbstractPDDL}(plan::T)
    return plan.goal_test(plan.kb);
end

function execute_action{T <: AbstractPDDL}(plan::T, action::Expression)
    local action_name::String = action.operator;
    local arguments::Tuple = action.arguments;
    local relevant_actions::AbstractVector = collect(a for a in plan.actions if (a.name == action_name));
    if (length(relevant_actions) == 0)
        error(@sprintf("execute_action(): Action \"%s\" not found!", action_name));
    else
        local first_relevant_action::PlanningAction = relevant_actions[1];
        if (!check_precondition(first_relevant_action, plan.kb, arguments))
            error(@sprintf("execute_action(): Action \"%s\" preconditions are not satisfied!", repr(action)));
        else
            execute_action(first_relevant_action, plan.kb, arguments);
        end
    end
    nothing;
end

function air_cargo_goal_test(kb::FirstOrderLogicKnowledgeBase)
    return all((function(ans)
                    if (typeof(ans) <: Bool)
                        return ans;
                    else
                        if (length(ans) == 0)   # length of Tuple
                            return false;
                        else
                            return true;
                        end
                    end
                end),
                collect(ask(kb, q) for q in (expr("At(C1, JFK)"), expr("At(C2, SFO)"))));
end

"""
    air_cargo_pddl()

Return a PDDL representing the air cargo transportation planning problem (Fig. 10.1).
"""
function air_cargo_pddl()
    local initial::Array{Expression, 1} = map(expr, ["At(C1, SFO)",
                                                "At(C2, JFK)",
                                                "At(P1, SFO)",
                                                "At(P2, JFK)",
                                                "Cargo(C1)",
                                                "Cargo(C2)",
                                                "Plane(P1)",
                                                "Plane(P2)",
                                                "Airport(JFK)",
                                                "Airport(SFO)"]);
    # Load Action Schema
    local precondition_positive::Array{Expression, 1} = map(expr, ["At(c, a)",
                                                            "At(p, a)",
                                                            "Cargo(c)",
                                                            "Plane(p)",
                                                            "Airport(a)"]);
    local precondition_negated::Array{Expression, 1} = [];
    local effect_add_list::Array{Expression, 1} = [expr("In(c, p)")];
    local effect_delete_list::Array{Expression, 1} = [expr("At(c, a)")];
    local load::PlanningAction = PlanningAction(expr("Load(c, p, a)"),
                                                (precondition_positive, precondition_negated),
                                                (effect_add_list, effect_delete_list));
    # Unload Action Schema
    precondition_positive = map(expr, ["In(c, p)", "At(p, a)", "Cargo(c)", "Plane(p)", "Airport(a)"]);
    precondition_negated = [];
    effect_add_list = [expr("At(c, a)")];
    effect_delete_list = [expr("In(c, p)")];
    local unload::PlanningAction = PlanningAction(expr("Unload(c, p, a)"),
                                                (precondition_positive, precondition_negated),
                                                (effect_add_list, effect_delete_list));
    # Fly Action Schema
    precondition_positive = map(expr, ["At(p, f)", "Plane(p)", "Airport(f)", "Airport(to)"]);
    precondition_negated = [];
    effect_add_list = [expr("At(p, to)")];
    effect_delete_list = [expr("At(p, f)")];
    local fly::PlanningAction = PlanningAction(expr("Fly(p, f, to)"),
                                                (precondition_positive, precondition_negated),
                                                (effect_add_list, effect_delete_list));
    return PDDL(initial, [load, unload, fly], air_cargo_goal_test);
end

function spare_tire_goal_test(kb::FirstOrderLogicKnowledgeBase)
    return all((function(ans)
                    if (typeof(ans) <: Bool)
                        return ans;
                    else
                        if (length(ans) == 0)   # length of Tuple
                            return false;
                        else
                            return true;
                        end
                    end
                end),
                collect(ask(kb, q) for q in (expr("At(Spare, Axle)"),)));
end

"""
    spare_tire_pddl()

Return a PDDL representing the spare tire planning problem (Fig. 10.2).
"""
function spare_tire_pddl()
    local initial::Array{Expression, 1} = map(expr, ["Tire(Flat)",
                                                    "Tire(Spare)",
                                                    "At(Flat, Axle)",
                                                    "At(Spare, Trunk)"]);
    # Remove Action Schema
    local precondition_positive::Array{Expression, 1} = [expr("At(obj, loc)")];
    local precondition_negated::Array{Expression, 1} = [];
    local effect_add_list::Array{Expression, 1} = [expr("At(obj, Ground)")];
    local effect_delete_list::Array{Expression, 1} = [expr("At(obj, loc)")];
    local remove::PlanningAction = PlanningAction(expr("Remove(obj, loc)"),
                                                (precondition_positive, precondition_negated),
                                                (effect_add_list, effect_delete_list));
    # PutOn Action Schema
    precondition_positive = map(expr, ["Tire(t)", "At(t, Ground)"]);
    precondition_negated = [expr("At(Flat, Axle)")];
    effect_add_list = [expr("At(t, Axle)")];
    effect_delete_list = [expr("At(t, Ground)")];
    local put_on::PlanningAction = PlanningAction(expr("PutOn(t, Axle)"),
                                                    (precondition_positive, precondition_negated),
                                                    (effect_add_list, effect_delete_list));
    # LeaveOvernight Action Schema
    precondition_positive = [];
    precondition_negated = [];
    effect_add_list = [];
    effect_delete_list = map(expr, ["At(Spare, Ground)", "At(Spare, Axle)", "At(Spare, Trunk)",
                                    "At(Flat, Ground)", "At(Flat, Axle)", "At(Flat, Trunk)"]);
    local leave_overnight::PlanningAction = PlanningAction(expr("LeaveOvernight"),
                                                            (precondition_positive, precondition_negated),
                                                            (effect_add_list, effect_delete_list));
    return PDDL(initial, [remove, put_on, leave_overnight], spare_tire_goal_test);
end

function three_block_tower_goal_test(kb::FirstOrderLogicKnowledgeBase)
    return all((function(ans)
                    if (typeof(ans) <: Bool)
                        return ans;
                    else
                        if (length(ans) == 0)   #length of Tuple
                            return false;
                        else
                            return true;
                        end
                    end
                end),
                collect(ask(kb, q) for q in (expr("On(A, B)"), expr("On(B, C)"))));
end

"""
    three_block_tower_pddl()

Return a PDDL representing the building of a three-block tower planning problem (Fig. 10.3).
"""
function three_block_tower_pddl()
    local initial::Array{Expression, 1} = map(expr, ["On(A, Table)",
                                                    "On(B, Table)",
                                                    "On(C, A)",
                                                    "Block(A)",
                                                    "Block(B)",
                                                    "Block(C)",
                                                    "Clear(B)",
                                                    "Clear(C)"]);
    # Move Action Schema
    local precondition_positive::Array{Expression, 1} = map(expr, ["On(b, x)", "Clear(b)", "Clear(y)", "Block(b)", "Block(y)"]);
    local precondition_negated::Array{Expression, 1} = [];
    local effect_add_list::Array{Expression, 1} = [expr("On(b, y)"), expr("Clear(x)")];
    local effect_delete_list::Array{Expression, 1} = [expr("On(b, x)"), expr("Clear(y)")];
    local move::PlanningAction = PlanningAction(expr("Move(b, x, y)"),
                                                (precondition_positive, precondition_negated),
                                                (effect_add_list, effect_delete_list));
    # MoveToTable Action Schema
    precondition_positive = map(expr, ["On(b, x)", "Clear(b)", "Block(b)"]);
    precondition_negated = [];
    effect_add_list = [expr("On(b, Table)"), expr("Clear(x)")];
    effect_delete_list = [expr("On(b, x)")];
    local move_to_table::PlanningAction = PlanningAction(expr("MoveToTable(b, x)"),
                                                        (precondition_positive, precondition_negated),
                                                        (effect_add_list, effect_delete_list));
    return PDDL(initial, [move, move_to_table], three_block_tower_goal_test);
end

function have_cake_and_eat_cake_too_goal_test(kb::FirstOrderLogicKnowledgeBase)
    return all((function(ans)
                    if (typeof(ans) <: Bool)
                        return ans;
                    else
                        if (length(ans) == 0)   # length of Tuple
                            return false;
                        else
                            return true;
                        end
                    end
                end),
                collect(ask(kb, q) for q in (expr("Have(Cake)"), expr("Eaten(Cake)"))));
end

"""
    have_cake_and_eat_cake_too_pddl()

Return a PDDL representing the 'have cake and eat cake too' planning problem (Fig. 10.7).
"""
function have_cake_and_eat_cake_too_pddl()
    local initial::Array{Expression, 1} = [expr("Have(Cake)")];
    # Eat Cake Action Schema
    local precondition_positive::Array{Expression, 1} = [expr("Have(Cake)")];
    local precondition_negated::Array{Expression, 1} = [];
    local effect_add_list::Array{Expression, 1} = [expr("Eaten(Cake)")];
    local effect_delete_list::Array{Expression, 1} = [expr("Have(Cake)")];
    local eat_cake::PlanningAction = PlanningAction(expr("Eat(Cake)"),
                                                    (precondition_positive, precondition_negated),
                                                    (effect_add_list, effect_delete_list));
    # Bake Cake Action Schema
    precondition_positive = [];
    precondition_negated = [expr("Have(Cake)")];
    effect_add_list = [expr("Have(Cake)")];
    effect_delete_list = [];
    local bake_cake::PlanningAction = PlanningAction(expr("Bake(Cake)"),
                                                    (precondition_positive, precondition_negated),
                                                    (effect_add_list, effect_delete_list));
    return PDDL(initial, [eat_cake, bake_cake], have_cake_and_eat_cake_too_goal_test);
end

