import Foundation

/// One bundled retrieval question contract.
///
/// `answer` is the canonical reference answer. `acceptedAnswers` contains only
/// meaning-preserving alternatives that can be scored by normalized exact match;
/// it is not a keyword rubric and never grants credit for a partial assertion.
struct NFRetrievalKnowledgeTarget: Equatable, Identifiable, Sendable {
    let id: String
    let field: STEMField
    let category: String
    let prompt: String
    let answer: String
    let acceptedAnswers: [String]
    let explanation: String

    var allAcceptedAnswers: [String] { [answer] + acceptedAnswers }

    /// A normalized prompt-answer contract used to detect semantic catalog
    /// collisions independently of the record's stable identifier.
    var semanticIdentity: String {
        [
            field.rawValue,
            NFBundledRetrievalCatalog.normalized(category),
            NFBundledRetrievalCatalog.normalized(prompt),
            NFBundledRetrievalCatalog.normalized(answer)
        ].joined(separator: "|")
    }
}

/// A code-signed, network-independent bank of 1,000 retrieval question
/// contracts: 200 editorial concept targets plus 800 computed instances across
/// 80 deterministic calculation families. The bank intentionally favors
/// durable textbook fundamentals over facts whose answer can expire, depend on
/// jurisdiction, or require individualized advice.
enum NFBundledRetrievalCatalog {
    static let version = 2
    static let editorialTargetCount = 200
    static let computedFamilyCount = 80
    static let computedTargetCount = 800
    static let requiredCountPerField = 125
    static let requiredTotalCount = requiredCountPerField * STEMField.allCases.count

    private static let reviewedTargets: [NFRetrievalKnowledgeTarget] = [
        // MARK: General STEM (25)
        k("independent-variable", .general, "experimental-design",
          "In a controlled experiment, what is the variable deliberately changed by the investigator?",
          "The independent variable", ["independent variable"],
          "The independent variable is deliberately manipulated so its relationship with a measured outcome can be examined."),
        k("dependent-variable", .general, "experimental-design",
          "In a controlled experiment, what is the measured outcome called?",
          "The dependent variable", ["dependent variable", "response variable"],
          "The dependent variable is the recorded response whose value may change when the independent variable changes."),
        k("control-group-purpose", .general, "experimental-design",
          "What is the main purpose of a control group in an experiment?",
          "To provide a comparison for the experimental condition", ["provide a baseline comparison", "provide a comparison group"],
          "A control group supplies a reference condition, making the observed difference between conditions interpretable."),
        k("random-assignment-purpose", .general, "experimental-design",
          "Why is random assignment used when allocating experimental units to conditions?",
          "To reduce systematic pre-existing differences between groups", ["reduce systematic baseline differences", "balance pre-existing differences on average"],
          "Random assignment makes systematic baseline imbalance less likely and supports comparison of the assigned conditions."),
        k("replication-purpose", .general, "experimental-design",
          "Why are independent replications valuable in empirical research?",
          "They test whether a result can be obtained again independently with new data", ["test whether the result can be independently obtained again", "check whether new independent data produce the result"],
          "Independent replication checks whether a finding persists when a new study obtains and analyzes new data, beyond one sample or research team."),
        k("falsifiable-hypothesis", .general, "scientific-method",
          "What property makes a scientific hypothesis falsifiable?",
          "A possible observation could show it to be false", ["it could be contradicted by evidence", "there is a conceivable test that could refute it"],
          "A falsifiable hypothesis rules out at least one possible observation instead of accommodating every conceivable result."),
        k("si-time-unit", .general, "measurement",
          "What is the SI base unit of time?",
          "second", ["the second", "s"],
          "The second is the International System of Units base unit used to measure time intervals."),
        k("precision-meaning", .general, "measurement",
          "What does high precision mean for repeated measurements?",
          "The repeated measurements are close to one another", ["repeat measurements closely agree", "the measurements have low spread"],
          "Precision describes repeatability or spread and does not by itself establish closeness to the true value."),
        k("accuracy-meaning", .general, "measurement",
          "What does measurement accuracy describe?",
          "Closeness to the accepted or true value", ["closeness to the true value", "closeness to an accepted reference value"],
          "Accuracy concerns agreement with a valid reference, whereas precision concerns agreement among repeated measurements."),
        k("dimensional-consistency", .general, "measurement",
          "What must be true of the physical dimensions on the two sides of a valid equation?",
          "They must be the same", ["the dimensions must match", "both sides must have identical dimensions"],
          "An equality between physical quantities is dimensionally consistent only when both sides have matching dimensions."),
        k("correlation-causation", .general, "evidence",
          "Does an observed correlation by itself establish that one variable causes the other?",
          "No", ["no it does not", "correlation alone does not establish causation"],
          "Correlation records association, while a causal conclusion also requires design or assumptions that address alternative explanations."),
        k("arithmetic-mean", .general, "data-literacy",
          "How is the arithmetic mean of a finite set of numbers calculated?",
          "Add the values and divide by the number of values", ["sum the values and divide by the count", "the sum divided by the number of observations"],
          "The arithmetic mean distributes the total of all observed values equally across the number of observations."),
        k("median-definition", .general, "data-literacy",
          "What is the median of an ordered data set?",
          "The middle value when the count is odd, or the mean of the two middle values when it is even", ["the central ordered value if the count is odd or the average of the two central values if it is even", "middle value for an odd count and mean of the middle pair for an even count"],
          "Ordering the observations locates the center; an even-sized set has two central observations whose mean is used."),
        k("proportion-definition", .general, "quantitative-reasoning",
          "How is a proportion formed from a part and its whole?",
          "Divide the part by the whole", ["part divided by whole", "the ratio of the part to the whole"],
          "A proportion compares a qualifying part with the complete reference total using the whole as denominator."),
        k("quarter-as-percent", .general, "quantitative-reasoning",
          "What percentage is equivalent to the decimal 0.25?",
          "25 percent", ["25%", "twenty-five percent"],
          "Multiplying the decimal by one hundred converts 0.25 to the equivalent percentage value of 25 percent."),
        k("unit-rate-definition", .general, "quantitative-reasoning",
          "What is a rate with a denominator of one unit called?",
          "A unit rate", ["unit rate"],
          "A unit rate expresses how much of one quantity corresponds to exactly one unit of another quantity."),
        k("graph-slope", .general, "data-literacy",
          "How is the slope between two points on a Cartesian graph calculated?",
          "Change in y divided by change in x", ["rise over run", "delta y divided by delta x"],
          "Slope measures vertical change per unit horizontal change, provided the two points have different x-coordinates."),
        k("direct-proportion-scaling", .general, "quantitative-reasoning",
          "If y is directly proportional to x, what happens to y when x doubles?",
          "y doubles", ["it doubles", "y is multiplied by two"],
          "Direct proportionality keeps the ratio y divided by x constant, so both quantities scale by the same factor."),
        k("inverse-proportion-scaling", .general, "quantitative-reasoning",
          "If y is inversely proportional to x, what happens to y when x doubles?",
          "y is halved", ["it is halved", "y becomes one half as large"],
          "Inverse proportionality keeps the product xy constant, so doubling one factor halves the other."),
        k("uncertainty-purpose", .general, "measurement",
          "Why is measurement uncertainty reported with a measured value?",
          "To communicate the range or degree of doubt in the measurement", ["show the measurement's uncertainty", "communicate the plausible range of the measured value"],
          "An uncertainty statement communicates limited measurement resolution and variability instead of presenting an estimate as exact."),
        k("sample-definition", .general, "data-literacy",
          "What is a sample relative to a population?",
          "A subset of the population that is observed", ["an observed subset of the population", "a subset selected from the population"],
          "A sample contains the units actually observed and is used to learn about the larger population of interest."),
        k("outlier-definition", .general, "data-literacy",
          "What is an outlier in a data set?",
          "An observation unusually far from the rest of the data", ["a value unusually distant from the other observations", "an unusually extreme observation"],
          "An outlier is unusually separated from the main pattern and should be investigated rather than automatically removed."),
        k("confound-definition", .general, "evidence",
          "In a causal exposure-outcome comparison, what makes a variable a potential confounder?",
          "It is a pre-exposure common cause of the exposure and outcome, not a mediator or collider", ["a common cause of exposure and outcome that occurs before exposure", "a pre-exposure cause shared by the exposure and outcome rather than a mediator or collider"],
          "Conditioning on an appropriate pre-exposure common cause can reduce confounding; descendants of exposure, mediators, and colliders require different treatment."),
        k("model-assumption", .general, "modeling",
          "What is a model assumption?",
          "A condition taken as given when constructing or applying the model", ["a condition the model treats as true", "a stated condition underlying the model"],
          "Assumptions define when a model's representation and conclusions are intended to apply and therefore require explicit checking."),
        k("counterexample-role", .general, "logic",
          "What can one valid counterexample establish about a universal claim?",
          "The universal claim is false", ["it disproves the universal claim", "the claim does not hold universally"],
          "A universal claim says every permitted case has a property, so one permitted case without it is decisive."),

        // MARK: Mathematics (25)
        k("additive-identity", .mathematics, "algebra",
          "What number is the additive identity for real numbers?",
          "0", ["zero"],
          "Adding zero leaves every real number unchanged, which is the defining property of the additive identity."),
        k("multiplicative-identity", .mathematics, "algebra",
          "What number is the multiplicative identity for real numbers?",
          "1", ["one"],
          "Multiplying by one leaves every real number unchanged, which is the defining property of the multiplicative identity."),
        k("division-by-zero", .mathematics, "algebra",
          "In ordinary real-number arithmetic, what is division by zero?",
          "undefined", ["it is undefined", "not defined"],
          "No real quotient can satisfy the inverse multiplication requirement because zero times every real number is zero."),
        k("distributive-property", .mathematics, "algebra",
          "How does multiplication distribute over addition in the expression a(b + c)?",
          "ab + ac", ["a times b plus a times c", "a b plus a c"],
          "The distributive property multiplies the outside factor by each addend while preserving their sum."),
        k("pythagorean-theorem", .mathematics, "geometry",
          "For a right triangle with legs a and b and hypotenuse c, what equation relates the side lengths?",
          "a squared plus b squared equals c squared", ["a^2 + b^2 = c^2", "a2 plus b2 equals c2"],
          "The Pythagorean theorem states that the square of a right triangle's hypotenuse equals the sum of the squared legs."),
        k("triangle-angle-sum", .mathematics, "geometry",
          "What is the sum of the interior angles of a Euclidean triangle?",
          "180 degrees", ["180°", "one hundred eighty degrees"],
          "In Euclidean geometry, a triangle's three interior angles together form a straight angle of 180 degrees."),
        k("constant-derivative", .mathematics, "calculus",
          "What is the derivative of a constant with respect to its variable?",
          "0", ["zero"],
          "A constant has no change as the variable changes, so its instantaneous rate of change is zero."),
        k("square-derivative", .mathematics, "calculus",
          "What is the derivative of x squared with respect to x?",
          "2x", ["two x", "2 times x"],
          "Applying the power rule lowers the exponent from two to one and multiplies by the original exponent."),
        k("integral-derivative-link", .mathematics, "calculus",
          "If F prime equals f, what is the definite integral of f from a to b?",
          "F(b) minus F(a)", ["F(b) - F(a)", "the antiderivative at b minus the antiderivative at a"],
          "The fundamental theorem of calculus connects accumulated change with the endpoint difference of an antiderivative."),
        k("quadratic-formula", .mathematics, "algebra",
          "For ax squared plus bx plus c equals zero with nonzero a, what formula gives x?",
          "negative b plus or minus the square root of b squared minus 4ac, all over 2a", ["(-b ± sqrt(b^2 - 4ac)) / (2a)", "minus b plus or minus root b squared minus four a c over two a"],
          "Completing the square for a general quadratic produces the two possible roots summarized by the quadratic formula."),
        k("two-point-midpoint", .mathematics, "coordinate-geometry",
          "How is the midpoint of Cartesian points (x1, y1) and (x2, y2) calculated?",
          "((x1 plus x2) divided by 2, (y1 plus y2) divided by 2)", ["((x1+x2)/2, (y1+y2)/2)", "average the x coordinates and average the y coordinates"],
          "A line segment's midpoint is found by independently averaging the two endpoint coordinates along each Cartesian axis."),
        k("logarithm-inverse", .mathematics, "functions",
          "What operation is a logarithm the inverse of?",
          "Exponentiation", ["raising a base to a power", "the exponential operation"],
          "A base-b logarithm returns the exponent to which b must be raised to obtain the specified positive number."),
        k("log-product-rule", .mathematics, "functions",
          "For positive x and y, what is log base b of xy equal to?",
          "log base b of x plus log base b of y", ["log_b(x) + log_b(y)", "log b x plus log b y"],
          "Multiplication inside a logarithm becomes addition because exponents add when powers with the same base are multiplied."),
        k("identity-matrix", .mathematics, "linear-algebra",
          "What square matrix leaves every compatible vector unchanged when multiplied by it?",
          "The identity matrix", ["identity matrix", "the appropriate identity matrix"],
          "The identity matrix has ones on its main diagonal and zeros elsewhere, so multiplication preserves every component."),
        k("two-by-two-determinant", .mathematics, "linear-algebra",
          "What is the determinant of the 2 by 2 matrix with rows (a, b) and (c, d)?",
          "ad minus bc", ["ad - bc", "a times d minus b times c"],
          "The two-by-two determinant subtracts the product of the off-diagonal entries from the product of the main diagonal entries."),
        k("eigenvector-definition", .mathematics, "linear-algebra",
          "What defining equation relates an eigenvector v of matrix A to its eigenvalue lambda?",
          "Av equals lambda v", ["A v = λ v", "A times v equals lambda times v"],
          "An eigenvector is a nonzero vector whose direction is preserved by the linear transformation, up to scalar multiplication."),
        k("prime-definition", .mathematics, "number-theory",
          "What is a prime number?",
          "An integer greater than one with exactly two positive divisors", ["a whole number greater than 1 divisible only by 1 and itself", "an integer above one whose positive divisors are one and itself"],
          "A prime's only positive divisors are one and the number itself, distinguishing it from composite integers."),
        k("greatest-common-divisor", .mathematics, "number-theory",
          "What is the greatest common divisor of two nonzero integers?",
          "The largest positive integer that divides both", ["the greatest positive common factor", "the largest positive divisor shared by both integers"],
          "The greatest common divisor is the largest positive member of the set of divisors shared by both integers."),
        k("even-integer-form", .mathematics, "number-theory",
          "How can every even integer be written using an integer k?",
          "2k", ["two k", "2 times k"],
          "Divisibility by two means precisely that the integer equals two multiplied by some integer k."),
        k("contrapositive", .mathematics, "logic",
          "What is the contrapositive of the implication 'if P, then Q'?",
          "If not Q, then not P", ["not Q implies not P", "if Q is false then P is false"],
          "An implication and its contrapositive are logically equivalent because both exclude the case where P is true and Q is false."),
        k("de-morgan-conjunction", .mathematics, "logic",
          "According to De Morgan's law, what is the negation of 'A and B'?",
          "not A or not B", ["¬A or ¬B", "A is false or B is false"],
          "A conjunction fails whenever at least one conjunct fails, so its negation is the disjunction of the two negations."),
        k("probability-complement", .mathematics, "probability",
          "If an event A has probability p, what is the probability that A does not occur?",
          "1 minus p", ["1 - p", "one minus p"],
          "An event and its complement partition all outcomes, so their probabilities sum exactly to one."),
        k("expected-value-definition", .mathematics, "probability",
          "How is the expected value of a discrete random variable calculated?",
          "Sum each possible value multiplied by its probability", ["the probability-weighted sum of all possible values", "add value times probability over all outcomes"],
          "Expected value is a probability-weighted average that includes every possible value in the random variable's distribution."),
        k("combination-order", .mathematics, "combinatorics",
          "In a combination, does the order of the selected objects matter?",
          "No", ["no it does not", "order does not matter"],
          "Combinations identify selected subsets, so rearranging the same selected objects does not create a new combination."),
        k("induction-components", .mathematics, "proof",
          "What two main components establish a proof by mathematical induction?",
          "A base case and an inductive step", ["prove the base case and prove the induction step", "base case plus inductive step"],
          "The base case starts the chain, and the inductive step shows that each established case implies the next one."),

        // MARK: Physics (25)
        k("force-si-unit", .physics, "mechanics",
          "What is the SI derived unit of force?",
          "newton", ["the newton", "N"],
          "One newton is the force required to accelerate one kilogram at one metre per second squared."),
        k("newton-second-law", .physics, "mechanics",
          "For constant mass, what equation relates net force, mass, and acceleration?",
          "F equals ma", ["F = ma", "net force equals mass times acceleration"],
          "Newton's second law states that net force equals mass multiplied by the resulting acceleration."),
        k("newton-third-law", .physics, "mechanics",
          "How are the two forces in a Newton's-third-law pair related?",
          "They are equal in magnitude and opposite in direction", ["equal and opposite", "same magnitude opposite directions"],
          "The paired forces act on different interacting bodies with equal magnitudes and opposite directions."),
        k("momentum-definition", .physics, "mechanics",
          "In classical nonrelativistic mechanics, what equation defines linear momentum for a particle of mass m and velocity v?",
          "p equals mv", ["p = mv", "momentum equals mass times velocity"],
          "In classical nonrelativistic mechanics, linear momentum is the scalar mass multiplied by the velocity vector."),
        k("kinetic-energy", .physics, "mechanics",
          "What is the classical kinetic energy of a mass m moving at speed v?",
          "one half mv squared", ["1/2 mv^2", "0.5 times m times v squared"],
          "Classical translational kinetic energy is one half the mass multiplied by the square of speed."),
        k("near-earth-potential-energy", .physics, "mechanics",
          "Near Earth's surface, what expression gives the change in gravitational potential energy for height h?",
          "mgh", ["mass times g times h", "delta U equals mgh"],
          "For approximately constant gravitational field strength, potential-energy change equals mass times g times vertical height change."),
        k("mechanical-power", .physics, "mechanics",
          "How is average mechanical power related to work and elapsed time?",
          "work divided by time", ["P = W/t", "power equals work over time"],
          "Average power measures the rate of energy transfer by dividing completed work by the elapsed time."),
        k("impulse-momentum", .physics, "mechanics",
          "What change in a body's motion equals the net impulse applied to it?",
          "The change in momentum", ["change in linear momentum", "delta p"],
          "The impulse-momentum theorem equates accumulated net force over time with the body's momentum change."),
        k("average-speed", .physics, "kinematics",
          "How is average speed calculated from total distance and total time?",
          "total distance divided by total time", ["distance over time", "total path length divided by elapsed time"],
          "Average speed uses the complete path length in the numerator and the complete elapsed interval in the denominator."),
        k("average-acceleration", .physics, "kinematics",
          "How is average acceleration calculated over a time interval?",
          "change in velocity divided by elapsed time", ["delta v over delta t", "velocity change divided by time"],
          "Average acceleration measures how much the velocity vector changes per unit elapsed time."),
        k("isolated-energy-conservation", .physics, "energy",
          "What happens to the total energy of an isolated system?",
          "It remains constant", ["total energy is conserved", "the system's total energy does not change"],
          "Energy can change form within an isolated system, but its total amount remains conserved."),
        k("frequency-period", .physics, "waves",
          "What equation relates frequency f and period T for a repeating motion?",
          "f equals one over T", ["f = 1/T", "frequency is the reciprocal of period"],
          "One period is the time for one cycle, so the number of cycles per unit time is its reciprocal."),
        k("wave-speed", .physics, "waves",
          "What equation relates wave speed v, frequency f, and wavelength lambda?",
          "v equals f lambda", ["v = fλ", "wave speed equals frequency times wavelength"],
          "During one period a wave advances one wavelength, giving speed equal to frequency multiplied by wavelength."),
        k("amplitude-definition", .physics, "waves",
          "What does the amplitude of a simple oscillation measure?",
          "The maximum displacement from equilibrium", ["maximum distance from equilibrium", "the magnitude of the greatest displacement from equilibrium"],
          "Amplitude records the largest magnitude of displacement on either side of the equilibrium position."),
        k("electric-current", .physics, "electricity",
          "How is average electric current related to transferred charge and elapsed time?",
          "charge divided by time", ["I = Q/t", "current equals charge per unit time"],
          "Electric current measures the rate at which charge crosses a chosen surface."),
        k("ohms-law", .physics, "electricity",
          "For an ohmic component, what equation relates voltage V, current I, and resistance R?",
          "V equals IR", ["V = IR", "voltage equals current times resistance"],
          "Ohm's law states that voltage across an ohmic component equals current through it times its resistance."),
        k("electric-power", .physics, "electricity",
          "What equation gives electric power from voltage V and current I?",
          "P equals VI", ["P = VI", "power equals voltage times current"],
          "Electrical power is the rate of energy transfer and equals potential difference multiplied by current."),
        k("series-current", .physics, "circuits",
          "In an ideal series circuit with one path, how does current compare through its components?",
          "The current is the same through every component", ["the same current flows through all components", "current is equal everywhere in the series path"],
          "A single unbranched path cannot accumulate charge at an ideal component, so the same current passes each component."),
        k("parallel-voltage", .physics, "circuits",
          "In an ideal parallel circuit, what electrical quantity is the same across every branch?",
          "voltage", ["potential difference", "the voltage across each branch"],
          "Every parallel branch connects to the same two nodes and therefore has the same potential difference."),
        k("charge-attraction", .physics, "electricity",
          "How do like electric charges and unlike electric charges interact?",
          "Like charges repel and unlike charges attract", ["same-sign charges repel and opposite-sign charges attract"],
          "The electrostatic force points apart for equal charge signs and together for opposite charge signs."),
        k("magnetic-poles", .physics, "magnetism",
          "How do like magnetic poles and unlike magnetic poles interact?",
          "Like poles repel and unlike poles attract", ["matching poles repel and opposite poles attract"],
          "Two north poles or two south poles repel, while a north pole and a south pole attract."),
        k("pressure-definition", .physics, "fluids",
          "How is average pressure calculated from perpendicular force and area?",
          "The magnitude of the perpendicular force divided by area", ["P = F/A", "normal force per unit area"],
          "Average pressure divides the magnitude of the perpendicular force by the surface area over which that force is distributed."),
        k("density-definition", .physics, "matter",
          "How is mass density calculated?",
          "mass divided by volume", ["rho equals mass over volume", "mass per unit volume"],
          "Mass density compares the amount of mass present with the volume occupied by that material."),
        k("temperature-si-unit", .physics, "thermodynamics",
          "What is the SI base unit of thermodynamic temperature?",
          "kelvin", ["the kelvin", "K"],
          "The kelvin is the SI base unit for thermodynamic temperature and uses an absolute zero reference."),
        k("sensible-heat-relation", .physics, "thermodynamics",
          "Without a phase change, what relation connects heat Q, mass m, specific heat c, and temperature change?",
          "Q equals mc delta T", ["Q = mcΔT", "heat equals mass times specific heat times temperature change"],
          "For constant specific heat and no phase change, transferred heat scales with mass and temperature change."),

        // MARK: Computing (25)
        k("binary-digit-values", .computing, "data-representation",
          "What two values can one binary digit represent?",
          "0 and 1", ["zero and one", "one or zero"],
          "A binary digit has two possible states, conventionally written as zero and one."),
        k("byte-size", .computing, "data-representation",
          "How many bits are in a byte?",
          "8", ["eight", "8 bits"],
          "A byte is conventionally defined as an ordered group of eight bits."),
        k("boolean-and", .computing, "boolean-logic",
          "When is the Boolean expression A AND B true?",
          "Only when both A and B are true", ["when A and B are both true", "both operands must be true"],
          "Logical conjunction returns true only for the input combination in which both operands are true."),
        k("boolean-or", .computing, "boolean-logic",
          "When is the inclusive Boolean expression A OR B true?",
          "When at least one of A or B is true", ["if either or both operands are true", "when A is true or B is true or both"],
          "Inclusive disjunction returns true for either true operand, including the case where both are true."),
        k("boolean-not", .computing, "boolean-logic",
          "What does the Boolean NOT operation do to a truth value?",
          "It reverses the truth value", ["it negates the value", "true becomes false and false becomes true"],
          "Logical negation maps true to false and maps false to true."),
        k("stack-order", .computing, "data-structures",
          "What removal order does a stack use?",
          "Last in, first out", ["LIFO", "the most recently added item is removed first"],
          "A stack exposes its top item, so the last element pushed is the first element popped."),
        k("queue-order", .computing, "data-structures",
          "What removal order does a standard queue use?",
          "First in, first out", ["FIFO", "the earliest added item is removed first"],
          "A queue removes from its front, preserving the arrival order of enqueued elements."),
        k("hash-table-average-lookup", .computing, "data-structures",
          "Under ordinary uniform-hashing assumptions, what is the average lookup complexity of a hash table?",
          "constant time", ["O(1)", "average O(1)"],
          "A well-distributed hash function usually directs lookup to a bounded bucket rather than scanning every stored item."),
        k("binary-search-precondition", .computing, "algorithms",
          "What ordering precondition does binary search require of its search range?",
          "The range must be sorted", ["sorted order", "the elements must be ordered by the comparison key"],
          "Binary search discards half the remaining range using order, so an unsorted range invalidates that decision."),
        k("binary-search-complexity", .computing, "algorithms",
          "What is the worst-case time complexity of binary search on a sorted array?",
          "O(log n)", ["logarithmic time", "log n"],
          "Each comparison halves the remaining candidate interval, producing logarithmic growth in the number of comparisons."),
        k("linear-search-complexity", .computing, "algorithms",
          "What is the worst-case time complexity of linear search through n items?",
          "O(n)", ["linear time", "n"],
          "A missing target or a target at the end can require examining every one of the n items."),
        k("breadth-first-frontier", .computing, "graph-algorithms",
          "Which data structure normally manages the frontier in breadth-first search?",
          "A queue", ["queue", "FIFO queue"],
          "A queue processes vertices in discovery order, which makes breadth-first search expand one distance layer at a time."),
        k("depth-first-frontier", .computing, "graph-algorithms",
          "Which data structure behavior normally manages the frontier in depth-first search?",
          "A stack", ["stack", "LIFO behavior", "the call stack"],
          "Stack behavior continues along the most recently discovered unfinished path before returning to earlier branches."),
        k("dijkstra-edge-condition", .computing, "graph-algorithms",
          "What condition on edge weights is required by the standard Dijkstra shortest-path algorithm?",
          "All edge weights must be nonnegative", ["nonnegative edge weights", "no negative-weight edges"],
          "A negative edge could improve a path after a vertex was finalized, breaking Dijkstra's greedy correctness argument."),
        k("topological-sort-domain", .computing, "graph-algorithms",
          "What kind of directed graph has a topological ordering?",
          "A directed acyclic graph", ["DAG", "a directed graph with no directed cycle"],
          "A directed cycle would require a vertex to come both before and after itself, so acyclicity is necessary."),
        k("tree-edge-count", .computing, "graph-theory",
          "How many edges does a finite tree with n vertices have?",
          "n minus 1", ["n - 1", "one fewer edge than vertices"],
          "A tree is connected without cycles, and adding each new vertex requires exactly one connecting edge."),
        k("loop-invariant", .computing, "program-correctness",
          "What must a loop invariant do throughout a correct loop?",
          "Remain true before and after every iteration", ["hold before and after each iteration", "be initialized and preserved by each iteration"],
          "A loop invariant supports correctness by holding initially, surviving each iteration, and helping establish the postcondition."),
        k("recursion-base-case", .computing, "program-correctness",
          "What is the purpose of a base case in a recursive algorithm?",
          "To stop recursion on a directly solvable input", ["provide a terminating case", "end the recursive calls"],
          "A base case returns without another recursive call, anchoring the computation and preventing unbounded descent."),
        k("stable-sort", .computing, "algorithms",
          "What property defines a stable sorting algorithm?",
          "It preserves the relative order of records with equal keys", ["equal-key items remain in their original relative order", "ties keep their input order"],
          "Stability ensures that sorting by one key does not reorder items that compare equal on that key."),
        k("database-primary-key", .computing, "databases",
          "What is the role of a primary key in a relational table?",
          "To uniquely identify each row", ["uniquely identify a record", "provide a unique identifier for every row"],
          "A primary key enforces a unique, non-null identity that other relations can reference."),
        k("inner-join", .computing, "databases",
          "Which rows does an inner join return?",
          "Rows with matching join conditions in both inputs", ["only matching rows from both tables", "rows that satisfy the join predicate on both sides"],
          "An inner join excludes input rows that have no partner satisfying the declared join condition."),
        k("deterministic-algorithm", .computing, "algorithms",
          "What makes an algorithm deterministic for a fixed input and fixed state?",
          "It produces the same behavior and result each time", ["the same input yields the same output", "repeated runs produce the same result under the same state"],
          "Determinism means no unresolved randomness or scheduling choice changes the algorithm's path or result under identical conditions."),
        k("unit-test", .computing, "software-testing",
          "What does a unit test usually check?",
          "One small component in isolation", ["an individual function or component", "a small isolated unit of behavior"],
          "A unit test narrows scope so a specific component's contract can be checked with controlled dependencies."),
        k("race-condition", .computing, "concurrency",
          "What is a race condition?",
          "A defect where behavior depends on the timing or ordering of concurrent operations", ["an outcome that depends on an uncontrolled interleaving", "a timing-dependent concurrency bug"],
          "A race occurs when concurrent accesses are not coordinated and different valid interleavings can produce different outcomes."),
        k("deadlock", .computing, "concurrency",
          "What is deadlock in a concurrent system?",
          "A state where tasks wait indefinitely for one another", ["cyclic waiting with no task able to proceed", "threads permanently waiting on each other"],
          "Deadlock prevents progress because every participant waits for a resource or event that another blocked participant must provide."),

        // MARK: Engineering (25)
        k("factor-of-safety", .engineering, "design-safety",
          "How is a factor of safety commonly defined from failure capacity and service demand expressed as like quantities?",
          "Failure capacity divided by service demand, using like quantities", ["failure load divided by service load", "failure stress divided by working stress"],
          "A factor of safety compares corresponding quantities: for example, failure load with service load or failure stress with working stress."),
        k("static-force-equilibrium", .engineering, "statics",
          "What must the vector sum of external forces equal for a body in static equilibrium?",
          "zero", ["0", "the net external force must be zero"],
          "Static equilibrium requires no translational acceleration, so all external forces must have a zero vector sum."),
        k("static-moment-equilibrium", .engineering, "statics",
          "What must the sum of external moments about any point equal in static equilibrium?",
          "zero", ["0", "the net external moment must be zero"],
          "Static equilibrium requires no angular acceleration, so clockwise and counterclockwise external moments must balance."),
        k("normal-stress", .engineering, "mechanics-of-materials",
          "How is average normal stress calculated from axial force and cross-sectional area?",
          "axial force divided by cross-sectional area", ["sigma equals F over A", "force per unit area"],
          "Average normal stress distributes the axial force uniformly over the section used in the idealized calculation."),
        k("engineering-strain", .engineering, "mechanics-of-materials",
          "How is engineering normal strain calculated from length change and original length?",
          "change in length divided by original length", ["delta L over L zero", "extension divided by initial length"],
          "Engineering strain normalizes elongation or contraction by the specimen's original gauge length."),
        k("youngs-modulus", .engineering, "mechanics-of-materials",
          "Within a linear elastic range, how is Young's modulus related to normal stress and strain?",
          "stress divided by strain", ["E equals sigma over epsilon", "the ratio of normal stress to normal strain"],
          "Young's modulus is the slope of the linear elastic stress-strain relation and measures axial stiffness."),
        k("torque-lever-arm", .engineering, "statics",
          "What product gives the magnitude of moment from a force perpendicular to its lever arm?",
          "force times perpendicular lever arm", ["F times d perpendicular", "force multiplied by moment arm"],
          "The perpendicular distance from the reference point to the force's line of action determines its turning effect."),
        k("free-body-diagram", .engineering, "statics",
          "What does a free-body diagram show after a body is isolated?",
          "All external forces and moments acting on the body", ["the external loads and reactions on the isolated body", "every external force and moment"],
          "A free-body diagram replaces surrounding connections with their external reactions so equilibrium equations can be written."),
        k("tolerance-definition", .engineering, "manufacturing",
          "What does an engineering tolerance specify?",
          "The permitted variation from a nominal value", ["allowable variation around the nominal dimension", "the acceptable range of variation"],
          "A tolerance defines acceptable limits so manufactured variation can be evaluated against functional requirements."),
        k("safety-margin", .engineering, "design-safety",
          "How is a simple safety margin calculated from capacity and demand?",
          "capacity minus demand", ["the difference between capacity and demand", "available capacity less required demand"],
          "A positive safety margin records how much predicted capacity remains after the specified demand is applied."),
        k("kirchhoff-current-law", .engineering, "circuits",
          "What does Kirchhoff's current law state at an ideal circuit node?",
          "The sum of currents entering equals the sum leaving", ["net current at a node is zero", "incoming current equals outgoing current"],
          "Charge does not accumulate at an ideal node, so the signed algebraic sum of branch currents is zero."),
        k("kirchhoff-voltage-law", .engineering, "circuits",
          "What does Kirchhoff's voltage law state around a closed ideal circuit loop?",
          "The signed sum of voltage changes is zero", ["the algebraic sum of voltages around the loop is zero", "voltage rises equal voltage drops"],
          "Returning to the same circuit node restores the original electric potential, so signed potential changes cancel."),
        k("negative-feedback", .engineering, "control-systems",
          "What does negative feedback do to a deviation between a system's output and reference?",
          "It drives the system in a direction that reduces the deviation", ["it opposes the error", "it acts to reduce the output-reference difference"],
          "Negative feedback uses the measured error to generate corrective action that opposes rather than reinforces the deviation."),
        k("open-loop-control", .engineering, "control-systems",
          "What distinguishes an open-loop controller from a closed-loop controller?",
          "It does not use measured output feedback", ["the output is not fed back", "control action does not depend on measured output"],
          "An open-loop controller issues commands without comparing the resulting measured output with the desired reference."),
        k("nyquist-sampling-condition", .engineering, "signals",
          "For a band-limited signal, what sampling-rate condition avoids ideal aliasing?",
          "The sampling rate must exceed twice the highest signal frequency", ["sample above two times the maximum frequency", "sampling frequency greater than 2 f max"],
          "Sampling above twice the highest present frequency keeps shifted spectral copies from overlapping in the ideal model."),
        k("aliasing-definition", .engineering, "signals",
          "What is aliasing in sampled-data systems?",
          "Different continuous frequencies become indistinguishable in the samples", ["a high frequency appears as a different lower frequency", "distinct signals produce the same sampled values"],
          "Insufficient sampling lets distinct continuous-time frequency components map to the same discrete sample pattern."),
        k("low-pass-filter", .engineering, "signals",
          "What frequency range does an ideal low-pass filter preserve?",
          "Frequencies below its cutoff", ["low frequencies below the cutoff", "components under the cutoff frequency"],
          "An ideal low-pass response transmits components below the cutoff while rejecting components above it."),
        k("linear-thermal-expansion", .engineering, "materials",
          "What relation gives a small unconstrained length change from thermal expansion?",
          "delta L equals alpha L delta T", ["ΔL = αLΔT", "length change equals expansion coefficient times original length times temperature change"],
          "For a constant linear expansion coefficient, length change scales with original length and temperature change."),
        k("beam-neutral-axis", .engineering, "mechanics-of-materials",
          "In elementary pure bending, what is the longitudinal normal stress at the neutral axis?",
          "zero", ["0", "the bending normal stress is zero"],
          "Fibres on the neutral axis have no longitudinal extension or contraction in the elementary bending model."),
        k("fatigue-definition", .engineering, "materials",
          "What loading pattern is associated with fatigue failure?",
          "Repeated or cyclic loading", ["cyclic stress", "many repeated load cycles"],
          "Fatigue damage accumulates under repeated stress cycles and can produce failure below a one-time static strength."),
        k("center-of-mass", .engineering, "mechanics",
          "How is the center-of-mass position formed from point masses and their positions?",
          "The mass-weighted average of the positions", ["sum of mass times position divided by total mass", "a weighted position average using mass"],
          "Each position contributes in proportion to its mass, and the weighted sum is normalized by total mass."),
        k("column-buckling", .engineering, "structures",
          "What instability can a slender member under axial compression experience?",
          "buckling", ["elastic buckling", "lateral buckling instability"],
          "A slender compressed member can lose its straight equilibrium shape through lateral deflection before material crushing."),
        k("resonance", .engineering, "dynamics",
          "What occurs when periodic forcing is near a lightly damped system's natural frequency?",
          "A large oscillation response can develop", ["resonance", "the response amplitude becomes large"],
          "Near a natural frequency, successive forcing cycles can add energy coherently and produce a large steady response."),
        k("sensor-role", .engineering, "systems",
          "What is the basic role of a sensor in an engineered system?",
          "To convert a physical quantity into a usable signal", ["measure a physical quantity and produce a signal", "transduce a physical input into a signal"],
          "A sensor transduces a physical property into information that can be observed, recorded, or used for control."),
        k("actuator-role", .engineering, "systems",
          "What is the basic role of an actuator in an engineered system?",
          "To convert a command signal into physical action", ["produce physical motion or force from a control signal", "turn a command into a physical output"],
          "An actuator receives an energy-bearing command and produces a physical change such as force, motion, or flow."),

        // MARK: Life sciences (25)
        k("cell-membrane", .lifeSciences, "cell-biology",
          "What broad role does the cell membrane perform?",
          "It selectively controls movement between the cell and its surroundings", ["it is a selective barrier around the cell", "regulate what enters and leaves the cell"],
          "The cell membrane separates internal contents from the environment while selectively permitting molecular transport and signaling."),
        k("dna-hereditary-information", .lifeSciences, "genetics",
          "What molecule stores hereditary information in cellular organisms?",
          "DNA", ["deoxyribonucleic acid"],
          "DNA's nucleotide sequence provides durable hereditary information that cells copy and pass to descendant cells."),
        k("rna-uracil", .lifeSciences, "molecular-biology",
          "Which nitrogenous base does RNA normally use in place of thymine?",
          "uracil", ["U"],
          "RNA normally contains uracil paired with adenine where DNA ordinarily uses thymine."),
        k("transcription", .lifeSciences, "molecular-biology",
          "What information transfer occurs during transcription?",
          "A DNA sequence is copied into RNA", ["DNA to RNA", "RNA is synthesized from a DNA template"],
          "During transcription, an RNA polymer is synthesized using one DNA strand as its sequence template."),
        k("translation", .lifeSciences, "molecular-biology",
          "What information transfer occurs during translation?",
          "An mRNA sequence directs synthesis of a polypeptide", ["mRNA to protein", "a protein is made from the messenger RNA code"],
          "Translation reads messenger-RNA codons and joins amino acids into a corresponding polypeptide chain."),
        k("ribosome-role", .lifeSciences, "cell-biology",
          "What cellular structure carries out translation?",
          "The ribosome", ["ribosome", "ribosomes"],
          "Ribosomes coordinate messenger RNA and transfer RNAs while catalyzing assembly of the polypeptide chain."),
        k("mitochondrion-role", .lifeSciences, "cell-biology",
          "What energy-related process is a principal function of mitochondria in eukaryotic cells?",
          "ATP production through cellular respiration", ["produce ATP by aerobic respiration", "cellular respiration"],
          "Mitochondria couple oxidation of fuel molecules to synthesis of much of a eukaryotic cell's ATP."),
        k("chloroplast-role", .lifeSciences, "cell-biology",
          "What major process occurs in chloroplasts of plants and algae?",
          "photosynthesis", ["light-driven photosynthesis", "conversion of light energy into chemical energy"],
          "Chloroplasts capture light energy and use it to support synthesis of energy-rich organic molecules."),
        k("enzyme-active-site", .lifeSciences, "biochemistry",
          "What region of an enzyme binds its substrate and supports catalysis?",
          "The active site", ["active site", "the enzyme's active site"],
          "The active site's three-dimensional chemical environment recognizes substrates and stabilizes the reaction pathway."),
        k("enzyme-denaturation", .lifeSciences, "biochemistry",
          "What happens to enzyme function when denaturation disrupts the required three-dimensional structure?",
          "The enzyme loses or reduces its catalytic activity", ["its activity decreases", "it can no longer catalyze effectively"],
          "Disrupting the folded structure alters the active site and therefore weakens or eliminates the enzyme's catalytic function."),
        k("genotype-definition", .lifeSciences, "genetics",
          "What does an organism's genotype describe?",
          "Its genetic constitution at the loci being considered", ["its allele combination", "the alleles it carries for the specified genes"],
          "Genotype records inherited allele states, whereas an observed trait may also reflect environment and biological context."),
        k("phenotype-definition", .lifeSciences, "genetics",
          "What does an organism's phenotype describe?",
          "Its observable traits", ["observable characteristics", "the traits that are expressed or measured"],
          "Phenotype comprises observable characteristics produced through interaction of genotype with developmental and environmental conditions."),
        k("allele-definition", .lifeSciences, "genetics",
          "In genetics, what is an allele?",
          "A variant form of a gene or genetic locus", ["a version of a gene", "an alternative sequence at a genetic locus"],
          "Alleles are alternative sequence forms at the same genomic locus and can contribute to inherited variation."),
        k("homozygous-definition", .lifeSciences, "genetics",
          "What does homozygous mean for a diploid organism at one locus?",
          "The two alleles at that locus are the same", ["it has two identical alleles", "both copies carry the same allele"],
          "A homozygous diploid has matching allele states on the two homologous chromosome copies at the locus."),
        k("heterozygous-definition", .lifeSciences, "genetics",
          "What does heterozygous mean for a diploid organism at one locus?",
          "The two alleles at that locus differ", ["it has two different alleles", "the homologous copies carry different alleles"],
          "A heterozygous diploid carries two different allele states at the specified genetic locus."),
        k("meiosis-ploidy", .lifeSciences, "cell-division",
          "What happens to chromosome-set number during meiosis that produces gametes?",
          "It is reduced from diploid to haploid", ["the chromosome-set number is halved", "meiosis produces haploid cells from a diploid precursor"],
          "Meiosis separates homologous chromosome sets so each resulting gamete receives one set rather than two."),
        k("mitosis-products", .lifeSciences, "cell-division",
          "What kind of daughter nuclei does an ordinary mitotic division produce before new mutation?",
          "Genetically similar daughter nuclei with the same chromosome set", ["two genetically similar nuclei", "daughter nuclei retaining the parental chromosome number"],
          "Mitosis separates replicated sister chromatids so each daughter nucleus receives a corresponding chromosome complement."),
        k("natural-selection", .lifeSciences, "evolution",
          "What process defines natural selection?",
          "Differential reproductive success associated with heritable variation", ["heritable variants differ in survival or reproduction", "differential reproduction of heritable traits"],
          "Natural selection changes variant frequencies when heritable differences are associated with different reproductive contributions."),
        k("mutation-variation", .lifeSciences, "evolution",
          "What process creates new DNA sequence variants?",
          "mutation", ["DNA mutation", "changes in DNA sequence"],
          "Mutation introduces sequence changes that provide new inherited variants on which other evolutionary processes can act."),
        k("primary-producer", .lifeSciences, "ecology",
          "What is a primary producer in an ecosystem?",
          "An organism that builds organic matter from inorganic sources using an energy source", ["an autotroph", "an organism that makes organic compounds from inorganic material"],
          "Primary producers introduce chemically stored energy and newly fixed organic matter into an ecosystem's food network."),
        k("population-definition", .lifeSciences, "ecology",
          "What is a biological population?",
          "Individuals of the same species living in the same area at the same time", ["members of one species in one area", "a local group of the same species"],
          "A population groups conspecific individuals whose occurrence overlaps in both geographic area and time."),
        k("community-definition", .lifeSciences, "ecology",
          "What is an ecological community?",
          "The populations of different species living and interacting in an area", ["all interacting populations in an area", "multiple species populations in the same place"],
          "A community contains the populations of multiple species and the biological interactions among them."),
        k("ecosystem-definition", .lifeSciences, "ecology",
          "What components make up an ecosystem?",
          "A biological community and its physical environment", ["organisms plus the abiotic environment", "the community and nonliving surroundings"],
          "An ecosystem includes living populations together with matter, energy, and physical conditions in their shared environment."),
        k("homeostasis", .lifeSciences, "physiology",
          "In physiology, what does homeostasis describe?",
          "Regulation that maintains internal conditions within functional ranges", ["maintenance of a relatively stable internal environment", "keeping internal variables within viable limits"],
          "Homeostatic processes sense deviations and coordinate responses that keep internal variables within workable ranges."),
        k("diffusion-direction", .lifeSciences, "cell-biology",
          "What is the net direction of passive diffusion for particles in a concentration gradient?",
          "From higher concentration toward lower concentration", ["down the concentration gradient", "from high to low concentration"],
          "Random molecular motion produces a net flux down the concentration gradient until the gradient is reduced."),

        // MARK: Chemistry (25)
        k("atom-definition", .chemistry, "atomic-structure",
          "In chemistry, what is an atom?",
          "The smallest unit of an element that retains that element's chemical identity", ["the basic unit of a chemical element", "a unit of an element retaining its chemical properties"],
          "An atom contains a nucleus and electrons and is the basic chemical unit used to describe an element."),
        k("atomic-number", .chemistry, "atomic-structure",
          "What particle count defines an element's atomic number?",
          "The number of protons in the nucleus", ["proton count", "number of protons"],
          "Each element is identified by its nuclear proton count, regardless of neutron count or ionic charge."),
        k("mass-number", .chemistry, "atomic-structure",
          "How is the mass number of a nuclide calculated?",
          "The number of protons plus the number of neutrons", ["protons plus neutrons", "total nucleons in the nucleus"],
          "Mass number counts the nucleons in one nucleus by adding its proton and neutron counts."),
        k("isotope-definition", .chemistry, "atomic-structure",
          "How do isotopes of the same element differ?",
          "They have different numbers of neutrons", ["different neutron counts", "same protons but different neutrons"],
          "Isotopes share the proton count that defines the element but contain different numbers of neutrons."),
        k("ion-definition", .chemistry, "atomic-structure",
          "What makes an atom or molecular group an ion?",
          "It has a net electric charge", ["it carries a nonzero net charge", "it is an atom or molecular entity with net charge"],
          "An ion is an atom or molecular entity with net charge; that charge can arise through electron, proton, or charged-group transfer."),
        k("cation-charge", .chemistry, "atomic-structure",
          "What sign of electric charge does a cation have?",
          "positive", ["a positive charge", "positively charged"],
          "A cation has fewer electrons than the neutral species and therefore carries a net positive charge."),
        k("anion-charge", .chemistry, "atomic-structure",
          "What sign of electric charge does an anion have?",
          "negative", ["a negative charge", "negatively charged"],
          "An anion has more electrons than the corresponding neutral species and therefore carries a net negative charge."),
        k("avogadro-constant", .chemistry, "amount-of-substance",
          "How many specified entities are in exactly one mole?",
          "6.02214076 times 10 to the 23", ["6.02214076 × 10^23", "6.02214076e23"],
          "The mole is defined by the exact Avogadro constant of 6.02214076 times ten to the twenty-third entities."),
        k("molar-mass", .chemistry, "amount-of-substance",
          "What does molar mass measure?",
          "Mass per mole of a substance", ["the mass of one mole", "mass divided by amount in moles"],
          "Molar mass connects a sample's measurable mass with its chemical amount expressed in moles."),
        k("equation-balancing", .chemistry, "stoichiometry",
          "What quantity for each element must a balanced chemical equation conserve?",
          "The number of atoms", ["atom count", "the count of each element's atoms"],
          "Balancing adjusts coefficients so every element has the same atom count before and after the reaction."),
        k("stoichiometric-coefficients", .chemistry, "stoichiometry",
          "What ratios do coefficients in a balanced chemical equation specify?",
          "Mole ratios among reactants and products", ["stoichiometric mole ratios", "relative amounts in moles"],
          "Equation coefficients give proportional numbers of formula units and therefore proportional chemical amounts in moles."),
        k("limiting-reactant", .chemistry, "stoichiometry",
          "What is the limiting reactant in a chemical reaction?",
          "The reactant consumed first according to the reaction stoichiometry", ["the reactant that runs out first", "the reactant that limits product formation"],
          "Once the limiting reactant is exhausted, the balanced reaction cannot form additional product even if other reactants remain."),
        k("theoretical-yield", .chemistry, "stoichiometry",
          "In reaction stoichiometry, what is theoretical yield?",
          "The maximum product amount predicted from stoichiometry", ["the stoichiometrically predicted maximum yield", "maximum possible product from the limiting reactant"],
          "Theoretical yield follows from the limiting reactant under the ideal assumption that the specified reaction goes completely."),
        k("percent-yield", .chemistry, "stoichiometry",
          "How is percent yield calculated?",
          "actual yield divided by theoretical yield times 100 percent", ["actual over theoretical times 100", "100% times actual yield over theoretical yield"],
          "Percent yield compares the product actually recovered with the maximum amount predicted by the stoichiometric calculation."),
        k("molarity", .chemistry, "solutions",
          "For a solution, how is molarity defined?",
          "Moles of solute per litre of solution", ["mol per liter of solution", "amount of solute divided by solution volume in litres"],
          "Molarity uses the complete solution volume, not solvent volume, as the denominator for solute amount."),
        k("dilution-relation", .chemistry, "solutions",
          "When solute amount is conserved during dilution, what relation connects initial and final molarity and volume?",
          "M1V1 equals M2V2", ["M1 V1 = M2 V2", "initial molarity times volume equals final molarity times volume"],
          "With no solute added or removed, concentration times solution volume represents the same solute amount before and after dilution."),
        k("ph-definition", .chemistry, "acid-base",
          "How is pH defined from hydrogen-ion activity in the usual dimensionless standard-state expression?",
          "negative base-10 logarithm of hydrogen-ion activity", ["pH = -log10(aH+)", "minus log base ten of hydrogen ion activity"],
          "The pH scale is logarithmic and is formally based on hydrogen-ion activity relative to a standard state."),
        k("bronsted-acid", .chemistry, "acid-base",
          "What is a Brønsted-Lowry acid?",
          "A proton donor", ["proton donor", "a species that donates H+"],
          "In the Brønsted-Lowry framework, an acid transfers a proton to a base in an acid-base reaction."),
        k("bronsted-base", .chemistry, "acid-base",
          "What is a Brønsted-Lowry base?",
          "A proton acceptor", ["proton acceptor", "a species that accepts H+"],
          "In the Brønsted-Lowry framework, a base accepts a proton donated by an acid."),
        k("catalyst-pathway", .chemistry, "kinetics",
          "How does a catalyst increase reaction rate?",
          "It provides an alternative pathway with lower activation energy", ["it lowers the activation-energy barrier", "an alternate lower-energy reaction pathway"],
          "A catalyst changes the available reaction mechanism so a greater fraction of collisions can cross the activation barrier."),
        k("dynamic-equilibrium", .chemistry, "equilibrium",
          "At dynamic chemical equilibrium, how do the forward and reverse reaction rates compare?",
          "They are equal", ["forward rate equals reverse rate", "the two rates are the same"],
          "Equal opposing rates keep macroscopic concentrations constant even though molecular reactions continue in both directions."),
        k("le-chatelier-principle", .chemistry, "equilibrium",
          "How does an equilibrium system respond to an imposed change according to Le Chatelier's principle?",
          "It shifts in the direction that partially opposes the change", ["the equilibrium shifts to counteract the disturbance", "it responds in a way that reduces the imposed change"],
          "Changing concentration, pressure, or temperature can alter the equilibrium composition toward the direction that reduces that perturbation."),
        k("exothermic-process", .chemistry, "thermochemistry",
          "What does an exothermic process do with heat?",
          "It releases heat to the surroundings", ["heat flows from the system to the surroundings", "the system gives off heat"],
          "Under the usual system-surroundings convention, an exothermic process transfers thermal energy from the system outward."),
        k("endothermic-process", .chemistry, "thermochemistry",
          "What does an endothermic process do with heat?",
          "It absorbs heat from the surroundings", ["heat flows into the system", "the system takes in heat"],
          "Under the usual system-surroundings convention, an endothermic process receives thermal energy from its surroundings."),
        k("ideal-gas-law", .chemistry, "gases",
          "What equation relates pressure, volume, amount, and absolute temperature for an ideal gas?",
          "PV equals nRT", ["PV = nRT", "pressure times volume equals moles times the gas constant times temperature"],
          "The ideal-gas equation connects the four macroscopic state variables through the molar gas constant."),

        // MARK: Data science (25)
        k("feature-definition", .dataScience, "machine-learning",
          "What is a feature in a predictive data set?",
          "An input variable used to make a prediction", ["predictor variable", "an input attribute supplied to the model"],
          "Features encode the measured inputs from which a predictive model constructs its output."),
        k("label-definition", .dataScience, "machine-learning",
          "What is a label in supervised learning?",
          "The target value the model is trained to predict", ["the prediction target", "the known target output"],
          "Supervised training pairs input features with labels that provide the target outcomes for learning."),
        k("training-set-role", .dataScience, "model-evaluation",
          "What is the role of a training set in supervised learning?",
          "To fit the model's learnable parameters", ["train the model", "estimate model parameters from examples"],
          "The training data directly influence fitted parameter values through the selected learning procedure."),
        k("validation-set-role", .dataScience, "model-evaluation",
          "What is the role of a validation set?",
          "To choose settings or models without using the final test set", ["tune hyperparameters", "select among candidate models"],
          "Validation evidence guides model and hyperparameter choices while preserving the test set for a later final evaluation."),
        k("test-set-role", .dataScience, "model-evaluation",
          "What is the role of a held-out test set?",
          "To estimate performance on unseen data after model choices are complete", ["evaluate final generalization", "provide a final out-of-sample performance estimate"],
          "A test set remains outside fitting and selection so its results provide a less biased final performance estimate."),
        k("data-leakage", .dataScience, "model-evaluation",
          "What is data leakage in a predictive modeling workflow?",
          "Information unavailable at a legitimate pipeline stage improperly influences preprocessing, fitting, selection, or evaluation", ["held-out future or deployment-unavailable information improperly enters the pipeline", "test-set information or prediction-time-unavailable information influences model development"],
          "Leakage includes partition contamination as well as features unavailable at deployment, and can make evaluation look unrealistically optimistic."),
        k("overfitting", .dataScience, "model-evaluation",
          "In predictive modeling, what is overfitting?",
          "Fitting training-specific noise or detail that does not generalize", ["performing well on training data but poorly on new data", "learning idiosyncrasies of the training set"],
          "An overfit model adapts too closely to its observed sample and therefore loses performance on genuinely new cases."),
        k("underfitting", .dataScience, "model-evaluation",
          "In predictive modeling, what is underfitting?",
          "Failing to capture important structure even in the training data", ["the model is too simple for the pattern", "poor fit to both training and new data"],
          "An underfit model lacks enough appropriate structure to represent the main relationship present in the data."),
        k("confusion-matrix", .dataScience, "classification",
          "What does a binary-classification confusion matrix tabulate?",
          "Counts of predicted classes against actual classes", ["true positives false positives true negatives and false negatives", "actual versus predicted class counts"],
          "A confusion matrix separates correct and incorrect predictions by both the observed class and the predicted class."),
        k("true-positive", .dataScience, "classification",
          "What is a true positive in binary classification?",
          "A positive case correctly predicted as positive", ["actual positive predicted positive", "a correctly identified positive"],
          "A true positive lies in the intersection of cases whose actual class and predicted class are both positive."),
        k("precision", .dataScience, "classification",
          "How is precision calculated for a positive class?",
          "true positives divided by true positives plus false positives", ["TP/(TP+FP)", "the fraction of positive predictions that are correct"],
          "Precision uses every predicted-positive case as its denominator and asks how many of those predictions were correct."),
        k("recall", .dataScience, "classification",
          "How is recall calculated for a positive class?",
          "true positives divided by true positives plus false negatives", ["TP/(TP+FN)", "the fraction of actual positives correctly found"],
          "Recall uses every actual-positive case as its denominator and asks how many the classifier successfully identified."),
        k("specificity", .dataScience, "classification",
          "How is specificity calculated for a negative class?",
          "true negatives divided by true negatives plus false positives", ["TN/(TN+FP)", "the fraction of actual negatives correctly identified"],
          "Specificity uses every actual-negative case as its denominator and measures the share correctly predicted negative."),
        k("classification-accuracy", .dataScience, "classification",
          "How is classification accuracy calculated?",
          "correct predictions divided by all predictions", ["true positives plus true negatives divided by total cases", "the fraction of cases classified correctly"],
          "Accuracy combines correctly predicted positive and negative cases and divides by the complete evaluated sample."),
        k("f1-score", .dataScience, "classification",
          "What two metrics are combined by the F1 score?",
          "precision and recall", ["precision with recall", "the harmonic mean of precision and recall"],
          "The F1 score is the harmonic mean of precision and recall, balancing the two through one summary."),
        k("regression-target", .dataScience, "machine-learning",
          "What type of target does a regression model ordinarily predict?",
          "A numerical value", ["a continuous numeric outcome", "a quantitative target"],
          "Regression estimates a number on a quantitative scale rather than selecting among discrete class labels."),
        k("classification-target", .dataScience, "machine-learning",
          "What type of target does a classification model predict?",
          "A category or class label", ["a categorical outcome", "one of a set of classes"],
          "Classification assigns an observation to a discrete category, possibly accompanied by class scores or probabilities."),
        k("residual-definition", .dataScience, "regression",
          "How is a regression residual commonly defined?",
          "observed value minus predicted value", ["y minus y hat", "actual outcome minus fitted outcome"],
          "A residual is the signed portion of an observed response that the fitted prediction did not account for."),
        k("mean-squared-error", .dataScience, "regression",
          "How is mean squared error calculated?",
          "Average the squared prediction errors", ["the mean of squared residuals", "sum squared errors divided by the number of cases"],
          "Squaring prevents positive and negative residuals from canceling and gives larger errors greater influence."),
        k("standardization", .dataScience, "preprocessing",
          "What transformation produces a standard score from a value, mean, and standard deviation?",
          "Subtract the mean and divide by the standard deviation", ["z equals x minus mean over standard deviation", "center by the mean then scale by standard deviation"],
          "Standardization centers the variable at zero and expresses deviations in units of its standard deviation."),
        k("one-hot-encoding", .dataScience, "preprocessing",
          "What does one-hot encoding create for a categorical variable?",
          "A binary indicator for each represented category", ["one binary column per category", "category indicator variables"],
          "Each indicator marks membership in one category without imposing a numeric order among category labels."),
        k("imputation", .dataScience, "preprocessing",
          "What is imputation in data preprocessing?",
          "Replacing missing values using a declared rule or estimate", ["filling in missing data", "assigning modeled or rule-based values to missing entries"],
          "Imputation supplies explicit replacement values so downstream methods can operate while the chosen assumptions remain reviewable."),
        k("cross-validation", .dataScience, "model-evaluation",
          "What does cross-validation repeatedly change when estimating model performance?",
          "Which observations are used for fitting and validation", ["the train-validation split", "the held-out fold"],
          "Cross-validation rotates held-out subsets so performance is evaluated across several complementary partitions of the available data."),
        k("random-seed", .dataScience, "reproducibility",
          "What does fixing a pseudorandom seed help reproduce?",
          "The same pseudorandom sequence and dependent randomized choices", ["the same random-number sequence", "repeatable pseudorandom results"],
          "A fixed seed initializes a deterministic pseudorandom generator state, making its subsequent sequence repeatable under the same implementation."),
        k("correlation-range", .dataScience, "statistics",
          "What range can a Pearson correlation coefficient take?",
          "from minus 1 to plus 1", ["-1 to 1", "between negative one and positive one"],
          "Pearson correlation is normalized to this closed interval, with sign indicating linear-association direction."),
    ]

    /// The 200 editorial concept targets are complemented by 800 computed
    /// instances across 80 deterministic calculation families. Each generated
    /// contract changes the authoritative givens and answer—not merely wording—
    /// and can be independently recomputed during release QA.
    static let targets: [NFRetrievalKnowledgeTarget] = reviewedTargets + computedTargets

    private static let computedTargets: [NFRetrievalKnowledgeTarget] =
        STEMField.allCases.flatMap { field in
            (0..<100).map { computedTarget(field: field, index: $0) }
        }

    private static func computedTarget(
        field: STEMField,
        index: Int
    ) -> NFRetrievalKnowledgeTarget {
        precondition((0..<100).contains(index))
        return switch field {
        case .general: computedGeneralTarget(index)
        case .mathematics: computedMathematicsTarget(index)
        case .physics: computedPhysicsTarget(index)
        case .computing: computedComputingTarget(index)
        case .engineering: computedEngineeringTarget(index)
        case .lifeSciences: computedLifeSciencesTarget(index)
        case .chemistry: computedChemistryTarget(index)
        case .dataScience: computedDataScienceTarget(index)
        }
    }

    private static func computedGeneralTarget(_ index: Int) -> NFRetrievalKnowledgeTarget {
        let step = index % 10
        switch index / 10 {
        case 0:
            let metres = step + 2
            let centimetres = metres * 100
            return k("metric-length-\(metres)m", .general, "measurement-calculation",
                     "How many centimetres are in exactly \(metres) metres?",
                     "\(centimetres) centimetres", ["\(centimetres) cm"],
                     "One metre contains one hundred centimetres, so multiplying by one hundred gives the converted length.")
        case 1:
            let minutes = step + 3
            let seconds = minutes * 60
            return k("time-conversion-\(minutes)min", .general, "measurement-calculation",
                     "How many seconds are in exactly \(minutes) minutes?",
                     "\(seconds) seconds", ["\(seconds) s"],
                     "Each minute contains sixty seconds, so the minute count is multiplied by sixty.")
        case 2:
            let first = step + 4
            let mean = first + 4
            return k("three-value-mean-\(first)", .general, "data-calculation",
                     "What is the arithmetic mean of \(first), \(first + 4), and \(first + 8)?",
                     "\(mean)", [],
                     "Adding the three equally spaced values and dividing by three gives their central value.")
        case 3:
            let part = (step + 1) * 5
            let percent = (step + 1) * 10
            return k("part-whole-percent-\(percent)", .general, "quantitative-calculation",
                     "What percentage of a whole of 50 is the part \(part)?",
                     "\(percent) percent", ["\(percent)%"],
                     "Dividing the part by fifty and multiplying by one hundred converts the proportion to percent.")
        case 4:
            let rate = step + 3
            let duration = step + 4
            let total = rate * duration
            return k("unit-rate-\(rate)-\(duration)", .general, "rate-calculation",
                     "A process produces \(total) items in \(duration) minutes at a constant rate. What is its unit rate?",
                     "\(rate) items per minute", ["\(rate) items/minute"],
                     "A constant unit rate equals the total item count divided by the complete elapsed time.")
        case 5:
            let final = 105 + step * 5
            let percent = final - 100
            return k("percent-increase-\(percent)", .general, "quantitative-calculation",
                     "A measured value rises from 100 to \(final). What is the percentage increase?",
                     "\(percent) percent", ["\(percent)%"],
                     "The increase is measured relative to the original value, which here is exactly one hundred.")
        case 6:
            let density = step + 2
            let volume = step + 3
            let mass = density * volume
            return k("density-\(mass)-\(volume)", .general, "measurement-calculation",
                     "A sample has mass \(mass) grams and volume \(volume) cubic centimetres. What is its density?",
                     "\(density) grams per cubic centimetre", ["\(density) g/cm^3"],
                     "Density is mass divided by volume, so the stated quantities give the requested unit rate.")
        case 7:
            let length = step + 3
            let width = step + 2
            let area = length * width
            return k("rectangle-area-\(length)-\(width)", .general, "measurement-calculation",
                     "What is the area of a rectangle \(length) metres long and \(width) metres wide?",
                     "\(area) square metres", ["\(area) m^2"],
                     "A rectangle's area equals its length multiplied by its perpendicular width.")
        case 8:
            let estimate = 20 + step * 2
            let uncertainty = step + 1
            let low = estimate - uncertainty
            let high = estimate + uncertainty
            return k("uncertainty-bounds-\(estimate)-\(uncertainty)", .general, "measurement-calculation",
                     "A result is reported as \(estimate) plus or minus \(uncertainty) units. What interval does that notation specify?",
                     "\(low) to \(high) units", ["[\(low), \(high)] units"],
                     "Subtracting and adding the stated absolute uncertainty gives the lower and upper interval endpoints.")
        default:
            let celsius = -5 + step * 5
            let kelvin = fixed(Double(celsius) + 273.15, places: 2)
            return k("celsius-kelvin-\(step)", .general, "measurement-calculation",
                     "Using K equals degrees Celsius plus 273.15, what is \(celsius) degrees Celsius in kelvin?",
                     "\(kelvin) kelvin", ["\(kelvin) K"],
                     "Adding the stated offset converts the Celsius reading to the absolute kelvin temperature scale.")
        }
    }

    private static func computedMathematicsTarget(_ index: Int) -> NFRetrievalKnowledgeTarget {
        let step = index % 10
        switch index / 10 {
        case 0:
            let value = step + 11
            return k("square-\(value)", .mathematics, "arithmetic-calculation",
                     "What is the exact square of the integer \(value)?",
                     "\(value * value)", [],
                     "Squaring an integer means multiplying that integer by itself exactly once.")
        case 1:
            let coefficient = step + 2
            let solution = step + 3
            let offset = step + 1
            let total = coefficient * solution + offset
            return k("linear-equation-\(coefficient)-\(offset)-\(total)", .mathematics, "algebra-calculation",
                     "What value of x solves \(coefficient)x plus \(offset) equals \(total)?",
                     "\(solution)", ["x = \(solution)"],
                     "Subtracting the constant and dividing by the nonzero coefficient isolates the unique solution.")
        case 2:
            let divisor = step + 2
            let first = divisor * 4
            let second = divisor * 9
            return k("gcd-\(first)-\(second)", .mathematics, "number-theory-calculation",
                     "What is the greatest common divisor of \(first) and \(second)?",
                     "\(divisor)", [],
                     "The cofactors four and nine are coprime, leaving the shared multiplier as the greatest common divisor.")
        case 3:
            let a = step + 2
            let b = 1
            let c = step + 1
            let d = 2
            let determinant = a * d - b * c
            return k("determinant-\(a)-\(c)", .mathematics, "linear-algebra-calculation",
                     "What is the determinant of the matrix with rows (\(a), \(b)) and (\(c), \(d))?",
                     "\(determinant)", [],
                     "For a two-by-two matrix, subtracting the off-diagonal product from the diagonal product gives the determinant.")
        case 4:
            let x1 = step
            let y1 = 2 * step + 1
            let slope = step + 2
            let x2 = x1 + 4
            let y2 = y1 + 4 * slope
            return k("slope-\(x1)-\(y1)-\(x2)-\(y2)", .mathematics, "coordinate-geometry-calculation",
                     "What is the slope between points (\(x1), \(y1)) and (\(x2), \(y2))?",
                     "\(slope)", [],
                     "Dividing the vertical coordinate change by the nonzero horizontal change gives the line's slope.")
        case 5:
            let x1 = step
            let y1 = 2 * step
            let x2 = x1 + 4
            let y2 = y1 + 6
            let midX = x1 + 2
            let midY = y1 + 3
            return k("midpoint-\(x1)-\(y1)-\(x2)-\(y2)", .mathematics, "coordinate-geometry-calculation",
                     "What is the midpoint of points (\(x1), \(y1)) and (\(x2), \(y2))?",
                     "(\(midX), \(midY))", [],
                     "A segment midpoint is obtained by averaging the two x coordinates and the two y coordinates separately.")
        case 6:
            let n = step + 5
            let combinations = n * (n - 1) / 2
            return k("unordered-pairs-\(n)", .mathematics, "combinatorics-calculation",
                     "How many unordered pairs can be selected from \(n) distinct objects?",
                     "\(combinations)", [],
                     "Choosing two objects without order gives n times n minus one divided by two.")
        case 7:
            let coefficient = step + 2
            let exponent = step + 2
            let derivativeCoefficient = coefficient * exponent
            let derivativeExponent = exponent - 1
            return k("monomial-derivative-\(coefficient)-\(exponent)", .mathematics, "calculus-calculation",
                     "What is the derivative with respect to x of \(coefficient)x^\(exponent)?",
                     "\(derivativeCoefficient)x^\(derivativeExponent)", [],
                     "The power rule multiplies by the original exponent and then lowers that exponent by one.")
        case 8:
            let constant = step + 2
            let upper = step + 3
            let integral = constant * upper
            return k("constant-integral-\(constant)-\(upper)", .mathematics, "calculus-calculation",
                     "What is the definite integral of the constant function \(constant) from 0 to \(upper)?",
                     "\(integral)", [],
                     "The accumulated area of a constant function is its height multiplied by the interval width.")
        default:
            let first = 30 + step
            let second = 50 + 2 * step
            let third = 180 - first - second
            return k("triangle-angle-\(first)-\(second)", .mathematics, "geometry-calculation",
                     "A Euclidean triangle has angles \(first) degrees and \(second) degrees. What is its third angle?",
                     "\(third) degrees", ["\(third)°"],
                     "The three interior angles total one hundred eighty degrees, so subtracting the known pair gives the third.")
        }
    }

    private static func computedPhysicsTarget(_ index: Int) -> NFRetrievalKnowledgeTarget {
        let step = index % 10
        switch index / 10 {
        case 0:
            let mass = step + 2
            let acceleration = step + 3
            let force = mass * acceleration
            return k("net-force-\(mass)-\(acceleration)", .physics, "mechanics-calculation",
                     "What net force accelerates a \(mass)-kilogram mass at \(acceleration) metres per second squared?",
                     "\(force) newtons", ["\(force) N"],
                     "For constant mass, Newton's second law gives net force as mass multiplied by acceleration.")
        case 1:
            let mass = step + 2
            let velocity = step + 4
            let momentum = mass * velocity
            return k("momentum-\(mass)-\(velocity)", .physics, "mechanics-calculation",
                     "In classical mechanics, what is the momentum of a \(mass)-kilogram object moving at \(velocity) metres per second?",
                     "\(momentum) kilogram metres per second", ["\(momentum) kg*m/s"],
                     "Classical linear momentum equals the object's mass multiplied by its velocity.")
        case 2:
            let mass = 2 * (step + 1)
            let speed = step + 2
            let energy = mass * speed * speed / 2
            return k("kinetic-energy-\(mass)-\(speed)", .physics, "energy-calculation",
                     "What is the classical kinetic energy of a \(mass)-kilogram mass moving at \(speed) metres per second?",
                     "\(energy) joules", ["\(energy) J"],
                     "Classical kinetic energy is one half of mass multiplied by the square of speed.")
        case 3:
            let current = step + 2
            let resistance = step + 3
            let voltage = current * resistance
            return k("ohm-voltage-\(current)-\(resistance)", .physics, "electricity-calculation",
                     "An ohmic resistor carries \(current) amperes and has resistance \(resistance) ohms. What voltage is across it?",
                     "\(voltage) volts", ["\(voltage) V"],
                     "Ohm's law gives voltage as current multiplied by resistance for an ohmic component.")
        case 4:
            let voltage = 5 * (step + 1)
            let current = step + 2
            let power = voltage * current
            return k("electric-power-\(voltage)-\(current)", .physics, "electricity-calculation",
                     "A device operates at \(voltage) volts while drawing \(current) amperes. What electrical power does it receive?",
                     "\(power) watts", ["\(power) W"],
                     "Electrical power equals the potential difference multiplied by the current through the device.")
        case 5:
            let frequency = step + 2
            let wavelength = step + 3
            let speed = frequency * wavelength
            return k("wave-speed-\(frequency)-\(wavelength)", .physics, "waves-calculation",
                     "A wave has frequency \(frequency) hertz and wavelength \(wavelength) metres. What is its propagation speed?",
                     "\(speed) metres per second", ["\(speed) m/s"],
                     "Wave speed is frequency multiplied by wavelength when both quantities describe the same wave.")
        case 6:
            let density = step + 2
            let volume = step + 5
            let mass = density * volume
            return k("mass-density-\(mass)-\(volume)", .physics, "matter-calculation",
                     "A uniform sample has mass \(mass) kilograms and volume \(volume) cubic metres. What is its density?",
                     "\(density) kilograms per cubic metre", ["\(density) kg/m^3"],
                     "Mass density is found by dividing the sample's mass by its occupied volume.")
        case 7:
            let pressure = 100 * (step + 1)
            let area = step + 2
            let force = pressure * area
            return k("average-pressure-\(force)-\(area)", .physics, "fluids-calculation",
                     "A perpendicular force of \(force) newtons is uniform over \(area) square metres. What is the average pressure?",
                     "\(pressure) pascals", ["\(pressure) Pa"],
                     "Average pressure equals the perpendicular force magnitude divided by the area carrying that force.")
        case 8:
            let speed = step + 10
            let time = step + 2
            let distance = speed * time
            return k("average-speed-\(distance)-\(time)", .physics, "kinematics-calculation",
                     "An object travels \(distance) metres in \(time) seconds. What is its average speed over the interval?",
                     "\(speed) metres per second", ["\(speed) m/s"],
                     "Average speed is total path length divided by the complete elapsed time interval.")
        default:
            let force = step + 5
            let time = step + 2
            let impulse = force * time
            return k("impulse-\(force)-\(time)", .physics, "mechanics-calculation",
                     "A constant net force of \(force) newtons acts for \(time) seconds. What impulse is delivered?",
                     "\(impulse) newton seconds", ["\(impulse) N*s"],
                     "For a constant force, impulse equals the net force multiplied by its duration.")
        }
    }

    private static func computedComputingTarget(_ index: Int) -> NFRetrievalKnowledgeTarget {
        let step = index % 10
        switch index / 10 {
        case 0:
            let bytes = step + 3
            let bits = bytes * 8
            return k("bytes-to-bits-\(bytes)", .computing, "data-representation-calculation",
                     "How many bits are contained in exactly \(bytes) bytes?",
                     "\(bits) bits", [],
                     "A byte contains eight bits, so multiplying the byte count by eight gives the total.")
        case 1:
            let kibibytes = step + 1
            let bytes = kibibytes * 1_024
            return k("kibibytes-to-bytes-\(kibibytes)", .computing, "data-representation-calculation",
                     "Using one kibibyte equals 1024 bytes, how many bytes are in \(kibibytes) kibibytes?",
                     "\(bytes) bytes", [],
                     "The binary prefix definition makes each kibibyte exactly one thousand twenty-four bytes.")
        case 2:
            let decimal = 18 + 7 * step
            let binary = String(decimal, radix: 2)
            return k("binary-to-decimal-\(binary)", .computing, "binary-calculation",
                     "What decimal integer is represented by the unsigned binary numeral \(binary)?",
                     "\(decimal)", [],
                     "Summing the powers of two selected by the one bits gives the decimal value.")
        case 3:
            let decimal = 33 + 5 * step
            let binary = String(decimal, radix: 2)
            return k("decimal-to-binary-\(decimal)", .computing, "binary-calculation",
                     "What unsigned binary numeral represents the decimal integer \(decimal)?",
                     "\(binary)", [],
                     "Repeated division by two or place-value decomposition produces the exact unsigned binary representation.")
        case 4:
            let bits = step + 3
            let patterns = 1 << bits
            return k("bit-pattern-count-\(bits)", .computing, "data-representation-calculation",
                     "How many distinct patterns can be represented by \(bits) independent bits?",
                     "\(patterns)", [],
                     "Each independent bit has two states, so the number of patterns is two raised to the bit count.")
        case 5:
            let decimal = 160 + 13 * step
            let hexadecimal = String(decimal, radix: 16).uppercased()
            let hexadecimalSlug = hexadecimal.lowercased()
            return k("hexadecimal-to-decimal-\(hexadecimalSlug)", .computing, "hexadecimal-calculation",
                     "What decimal integer is represented by the hexadecimal numeral \(hexadecimal)?",
                     "\(decimal)", [],
                     "Hexadecimal place values are powers of sixteen, so expanding the numeral yields the decimal integer.")
        case 6:
            let length = 5 + 3 * step
            let lastIndex = length - 1
            return k("zero-based-last-index-\(length)", .computing, "array-calculation",
                     "In a zero-based array containing \(length) elements, what is the last valid index?",
                     "\(lastIndex)", [],
                     "Zero-based indexing begins at zero, making the final valid index one less than the element count.")
        case 7:
            let lower = step + 2
            let upper = lower + step + 4
            let iterations = upper - lower + 1
            return k("inclusive-loop-\(lower)-\(upper)", .computing, "algorithm-tracing",
                     "A loop visits every integer from \(lower) through \(upper), including both endpoints. How many iterations run?",
                     "\(iterations)", [],
                     "An inclusive integer interval contains upper minus lower plus one distinct values.")
        case 8:
            let rate = 1_000 * (step + 2)
            let seconds = step + 3
            let bytes = rate * seconds
            return k("data-transfer-\(rate)-\(seconds)", .computing, "networking-calculation",
                     "At a constant payload rate of \(rate) bytes per second for \(seconds) seconds, how many bytes transfer?",
                     "\(bytes) bytes", [],
                     "With no overhead included, transferred payload equals the constant byte rate multiplied by elapsed time.")
        default:
            let pixels = 100 * (step + 1)
            let bits = pixels * 24
            return k("rgb-storage-\(pixels)", .computing, "data-representation-calculation",
                     "Without compression or padding, how many bits store \(pixels) RGB pixels at 8 bits per channel?",
                     "\(bits) bits", [],
                     "Three color channels at eight bits each require twenty-four bits for every pixel.")
        }
    }

    private static func computedEngineeringTarget(_ index: Int) -> NFRetrievalKnowledgeTarget {
        let step = index % 10
        switch index / 10 {
        case 0:
            let stress = 10 * (step + 1)
            let area = step + 2
            let force = stress * area
            return k("normal-stress-\(force)-\(area)", .engineering, "mechanics-calculation",
                     "A perpendicular load of \(force) newtons acts over \(area) square millimetres. What is the average normal stress?",
                     "\(stress) megapascals", ["\(stress) MPa"],
                     "One newton per square millimetre equals one megapascal, and stress is load divided by area.")
        case 1:
            let elongation = step + 1
            let strain = fixed(Double(elongation) / 1_000, places: 3)
            let compactStrain = compactPOSIXDecimal(strain)
            return k("engineering-strain-\(elongation)-1000", .engineering, "mechanics-calculation",
                     "A 1000-millimetre member extends by \(elongation) millimetres. What is its dimensionless engineering strain?",
                     strain, compactStrain == strain ? [] : [compactStrain],
                     "Engineering strain equals extension divided by original length, so the millimetre units cancel.")
        case 2:
            let safetyFactor = step + 2
            let serviceLoad = 100 * (step + 1)
            let failureLoad = safetyFactor * serviceLoad
            return k("factor-of-safety-\(failureLoad)-\(serviceLoad)", .engineering, "design-calculation",
                     "A component fails at \(failureLoad) newtons and carries \(serviceLoad) newtons. What is its load-based factor of safety?",
                     "\(safetyFactor)", [],
                     "A load-based factor of safety divides failure load by service load using like quantities.")
        case 3:
            let inputForce = step + 5
            let advantage = step + 2
            let outputForce = inputForce * advantage
            return k("mechanical-advantage-\(outputForce)-\(inputForce)", .engineering, "machines-calculation",
                     "An ideal machine produces \(outputForce) newtons from \(inputForce) newtons of input force. What is its mechanical advantage?",
                     "\(advantage)", [],
                     "Ideal mechanical advantage is output force divided by input force for the same machine.")
        case 4:
            let percent = 50 + step * 5
            let inputEnergy = 1_000
            let usefulEnergy = percent * 10
            return k("efficiency-\(usefulEnergy)-\(inputEnergy)", .engineering, "energy-calculation",
                     "A system receives \(inputEnergy) joules and delivers \(usefulEnergy) joules usefully. Express the result as a percentage: what is its efficiency?",
                     "\(percent) percent", ["\(percent)%"],
                     "Efficiency is useful output energy divided by input energy and then expressed as a percentage.")
        case 5:
            let force = step + 10
            let arm = step + 2
            let torque = force * arm
            return k("torque-\(force)-\(arm)", .engineering, "mechanics-calculation",
                     "A \(force)-newton force acts perpendicular to a \(arm)-metre lever arm. What torque magnitude results?",
                     "\(torque) newton metres", ["\(torque) N*m"],
                     "A perpendicular force produces torque equal to force magnitude multiplied by lever-arm length.")
        case 6:
            let flowRate = step + 3
            let time = step + 4
            let volume = flowRate * time
            return k("volume-flow-\(volume)-\(time)", .engineering, "fluids-calculation",
                     "A line carries \(volume) litres uniformly in \(time) seconds. What is the volumetric flow rate?",
                     "\(flowRate) litres per second", ["\(flowRate) L/s"],
                     "Volumetric flow rate is transported volume divided by the elapsed transfer time.")
        case 7:
            let first = step + 2
            let second = step + 4
            let third = step + 6
            let total = first + second + third
            return k("series-resistance-\(first)-\(second)-\(third)", .engineering, "circuits-calculation",
                     "Three resistors of \(first), \(second), and \(third) ohms are connected in series. What is their equivalent resistance?",
                     "\(total) ohms", ["\(total) Ω"],
                     "Ideal series resistances add because the same current passes through every component.")
        case 8:
            let driver = 20
            let driven = 40 + 10 * step
            let ratio = fixed(Double(driven) / Double(driver), places: 1)
            let compactRatio = compactPOSIXDecimal(ratio)
            var alternatives = ["\(ratio):1"]
            if compactRatio != ratio {
                alternatives += ["\(compactRatio) to 1", "\(compactRatio):1"]
            }
            return k("gear-ratio-\(driver)-\(driven)", .engineering, "machines-calculation",
                     "A \(driver)-tooth driver gear meshes with a \(driven)-tooth driven gear. What is the driven-to-driver tooth ratio?",
                     "\(ratio) to 1", alternatives,
                     "The requested tooth ratio divides the driven gear tooth count by the driver tooth count.")
        default:
            let time = step + 2
            let power = 100 * (step + 1)
            let work = power * time
            return k("mechanical-power-\(work)-\(time)", .engineering, "energy-calculation",
                     "A machine performs \(work) joules of work in \(time) seconds. What is its average mechanical power?",
                     "\(power) watts", ["\(power) W"],
                     "Average mechanical power is completed work divided by the elapsed time interval.")
        }
    }

    private static func computedLifeSciencesTarget(_ index: Int) -> NFRetrievalKnowledgeTarget {
        let step = index % 10
        let dnaSequences = [
            "ATGCCA", "CGTATA", "GGCATT", "TACGGA", "ACCTGT",
            "GTAGCC", "CATGAT", "TTGCGA", "AGTCCT", "CGAAGT"
        ]
        switch index / 10 {
        case 0:
            let sequence = dnaSequences[step]
            let complement = dnaComplement(sequence)
            return k("dna-complement-\(step + 1)", .lifeSciences, "genetics-calculation",
                     "For the DNA bases 5'-\(sequence)-3', what complementary bases align beneath them in the 3'-to-5' direction?",
                     "3'-\(complement)-5'", [complement],
                     "DNA base pairing aligns adenine with thymine and cytosine with guanine on antiparallel strands.")
        case 1:
            let codingDNA = dnaSequences[step]
            let messengerRNA = codingDNA.replacingOccurrences(of: "T", with: "U")
            return k("coding-dna-to-mrna-\(step + 1)", .lifeSciences, "molecular-biology-calculation",
                     "Ignoring RNA processing, what 5'-to-3' mRNA sequence matches the coding DNA strand 5'-\(codingDNA)-3'?",
                     "5'-\(messengerRNA)-3'", [messengerRNA],
                     "Messenger RNA matches the coding DNA strand except that uracil replaces thymine.")
        case 2:
            let aminoAcids = step + 10
            let nucleotides = aminoAcids * 3
            return k("coding-length-\(nucleotides)", .lifeSciences, "molecular-biology-calculation",
                     "Ignoring a stop codon, how many amino acids are encoded by \(nucleotides) coding nucleotides?",
                     "\(aminoAcids) amino acids", [],
                     "Each amino acid is specified by one codon containing exactly three coding nucleotides.")
        case 3:
            let initialCells = step + 5
            let doublings = step % 5 + 2
            let finalCells = initialCells * (1 << doublings)
            return k("cell-doubling-\(initialCells)-\(doublings)", .lifeSciences, "population-calculation",
                     "Starting with \(initialCells) cells, how many cells result after \(doublings) complete doublings with no losses?",
                     "\(finalCells) cells", [],
                     "Each complete doubling multiplies the population by two, so repeated doublings use a power of two.")
        case 4:
            let actualSize = step + 2
            let magnification = 100 * (step + 1)
            let imageSize = actualSize * magnification
            return k("microscopy-size-\(imageSize)-\(magnification)", .lifeSciences, "microscopy-calculation",
                     "A structure appears \(imageSize) micrometres long at \(magnification)-fold magnification. What is its actual length?",
                     "\(actualSize) micrometres", ["\(actualSize) µm"],
                     "Actual size equals measured image size divided by the stated linear magnification.")
        case 5:
            let side = step + 1
            let area = 6 * side * side
            return k("cube-surface-area-\(side)", .lifeSciences, "cell-geometry-calculation",
                     "A cubic model cell has side length \(side) micrometres. What is its total surface area?",
                     "\(area) square micrometres", ["\(area) µm^2"],
                     "A cube has six congruent square faces, each with area equal to side squared.")
        case 6:
            let side = step + 1
            let volume = side * side * side
            return k("cube-volume-\(side)", .lifeSciences, "cell-geometry-calculation",
                     "A cubic model cell has side length \(side) micrometres. What is its volume?",
                     "\(volume) cubic micrometres", ["\(volume) µm^3"],
                     "A cube's volume is the product of its three equal side lengths.")
        case 7:
            let initial = 100 + 10 * step
            let births = 20 + 2 * step
            let deaths = 5 + step
            let immigration = 8 + step
            let emigration = 3
            let final = initial + births - deaths + immigration - emigration
            return k("population-balance-\(step + 1)", .lifeSciences, "ecology-calculation",
                     "A population starts at \(initial), with \(births) births, \(deaths) deaths, \(immigration) immigrants, and \(emigration) emigrants. What is its final size?",
                     "\(final)", [],
                     "Population balance adds births and immigration while subtracting deaths and emigration from the initial count.")
        case 8:
            let grossProduction = 100 + 10 * step
            let respiration = 20 + 3 * step
            let netProduction = grossProduction - respiration
            return k("net-primary-production-\(grossProduction)-\(respiration)", .lifeSciences, "ecology-calculation",
                     "An ecosystem's gross primary production is \(grossProduction) units and producer respiration is \(respiration) units. What is net primary production?",
                     "\(netProduction) units", [],
                     "Net primary production is gross primary production minus the producers' respiratory energy use.")
        default:
            let qPercent = 5 * (step + 1)
            let exact = fixed(Double(qPercent * qPercent) / 100, places: qPercent % 10 == 0 ? 0 : 2)
            return k("hardy-weinberg-recessive-\(qPercent)", .lifeSciences, "population-genetics-calculation",
                     "Under Hardy-Weinberg assumptions, a recessive allele frequency is \(qPercent) percent. What percentage has the homozygous recessive genotype?",
                     "\(exact) percent", ["\(exact)%"],
                     "Hardy-Weinberg equilibrium assigns the homozygous recessive genotype frequency as q squared.")
        }
    }

    private static func computedChemistryTarget(_ index: Int) -> NFRetrievalKnowledgeTarget {
        let step = index % 10
        switch index / 10 {
        case 0:
            let atoms: [(symbol: String, atomicNumber: Int, charge: Int)] = [
                ("Li", 3, 1), ("Be", 4, 2), ("F", 9, -1), ("Na", 11, 1), ("Mg", 12, 2),
                ("Al", 13, 3), ("Cl", 17, -1), ("K", 19, 1), ("Ca", 20, 2), ("O", 8, -2)
            ]
            let atom = atoms[step]
            let electrons = atom.atomicNumber - atom.charge
            let chargeText = atom.charge > 0 ? "+\(atom.charge)" : "\(atom.charge)"
            return k("ion-electrons-\(atom.symbol.lowercased())-\(chargeText.replacingOccurrences(of: "+", with: "plus").replacingOccurrences(of: "-", with: "minus"))",
                     .chemistry, "atomic-structure-calculation",
                     "An \(atom.symbol) ion has atomic number \(atom.atomicNumber) and charge \(chargeText). How many electrons does it contain?",
                     "\(electrons) electrons", [],
                     "Ion electron count equals atomic number minus the signed ionic charge.")
        case 1:
            let compounds: [(slug: String, formula: String, mass: Int)] = [
                ("water", "H2O", 18), ("carbon-dioxide", "CO2", 44), ("methane", "CH4", 16),
                ("ammonia", "NH3", 17), ("sodium-chloride", "NaCl", 58), ("oxygen", "O2", 32),
                ("nitrogen", "N2", 28), ("sulfur-dioxide", "SO2", 64), ("calcium-oxide", "CaO", 56),
                ("magnesium-oxide", "MgO", 40)
            ]
            let compound = compounds[step]
            return k("molar-mass-\(compound.slug)", .chemistry, "stoichiometry-calculation",
                     "Using rounded atomic masses H=1, C=12, N=14, O=16, Na=23, Mg=24, S=32, Cl=35, and Ca=40, what is the molar mass of \(compound.formula)?",
                     "\(compound.mass) grams per mole", ["\(compound.mass) g/mol"],
                     "Adding each element's stated atomic mass with its formula subscript gives the compound's molar mass.")
        case 2:
            let molarMass = 10 * (step + 2)
            let moles = step + 1
            let mass = molarMass * moles
            return k("mass-to-moles-\(mass)-\(molarMass)", .chemistry, "stoichiometry-calculation",
                     "A substance has molar mass \(molarMass) grams per mole. How many moles are in \(mass) grams?",
                     "\(moles) moles", ["\(moles) mol"],
                     "Amount in moles equals sample mass divided by the substance's molar mass.")
        case 3:
            let moles = step + 1
            let coefficient = 6 * moles
            let normalizedCoefficient = fixed(Double(coefficient) / 10, places: 1)
            let canonicalAnswer = moles == 1
                ? "6 × 10^23 particles"
                : "\(normalizedCoefficient) × 10^24 particles"
            let productForm = "\(coefficient) × 10^23 particles"
            var alternatives = moles == 1 ? [] : [productForm]
            let compactCoefficient = compactPOSIXDecimal(normalizedCoefficient)
            if moles > 1, compactCoefficient != normalizedCoefficient {
                alternatives.append("\(compactCoefficient) × 10^24 particles")
            }
            return k("particle-count-\(moles)", .chemistry, "stoichiometry-calculation",
                     "Using exactly 6 times 10^23 particles per mole, how many particles are in \(moles) moles?",
                     canonicalAnswer, alternatives,
                     "Multiplying the stated particles-per-mole constant by the amount in moles gives the particle count.")
        case 4:
            let initialVolume = 5 * (step + 1)
            let finalConcentration = fixed(Double(initialVolume) / 100, places: 2)
            let compactConcentration = compactPOSIXDecimal(finalConcentration)
            var alternatives = ["\(finalConcentration) M"]
            if compactConcentration != finalConcentration {
                alternatives += [
                    "\(compactConcentration) moles per litre",
                    "\(compactConcentration) M"
                ]
            }
            return k("dilution-\(initialVolume)-100", .chemistry, "solutions-calculation",
                     "A \(initialVolume)-millilitre sample of a 1.0-molar solution is diluted to 100 millilitres. What is the final concentration?",
                     "\(finalConcentration) moles per litre", alternatives,
                     "Conservation of solute gives initial concentration times volume equal to final concentration times volume.")
        case 5:
            let exponent = step + 1
            return k("hydrogen-activity-ph-\(exponent)", .chemistry, "acid-base-calculation",
                     "Using pH equals negative log base ten of hydrogen-ion activity, what pH corresponds to an activity of 1 times 10^-\(exponent)?",
                     "\(exponent)", ["pH \(exponent)"],
                     "The negative base-ten logarithm of ten raised to the negative exponent equals that positive exponent.")
        case 6:
            let density = step + 1
            let volume = step + 10
            let mass = density * volume
            return k("sample-density-\(mass)-\(volume)", .chemistry, "measurement-calculation",
                     "A sample has mass \(mass) grams and volume \(volume) millilitres. What is its density?",
                     "\(density) grams per millilitre", ["\(density) g/mL"],
                     "Density equals mass divided by volume with the corresponding compound measurement units.")
        case 7:
            let moles = step + 1
            let volume = 24 * moles
            return k("molar-gas-volume-\(moles)", .chemistry, "gas-calculation",
                     "At conditions where molar gas volume is exactly 24 litres per mole, what volume do \(moles) moles occupy?",
                     "\(volume) litres", ["\(volume) L"],
                     "At the specified conditions, gas volume equals amount in moles multiplied by molar volume.")
        case 8:
            let soluteMass = 5 * (step + 1)
            let percent = soluteMass
            return k("mass-percent-\(soluteMass)-100", .chemistry, "solutions-calculation",
                     "A 100-gram mixture contains \(soluteMass) grams of solute. What is the solute mass percentage?",
                     "\(percent) percent", ["\(percent)%"],
                     "Mass percentage is solute mass divided by total mixture mass and multiplied by one hundred.")
        default:
            let acidConcentrationTenths = step + 1
            let acidVolume = 10
            let baseConcentrationTenths = 1
            let baseVolume = acidConcentrationTenths * acidVolume / baseConcentrationTenths
            let acidConcentration = fixed(Double(acidConcentrationTenths) / 10, places: 1)
            return k("neutralization-volume-\(acidConcentrationTenths)", .chemistry, "stoichiometry-calculation",
                     "For a one-to-one neutralization, what volume of 0.1-molar base neutralizes 10 millilitres of \(acidConcentration)-molar acid?",
                     "\(baseVolume) millilitres", ["\(baseVolume) mL"],
                     "One-to-one stoichiometry equates acid concentration-volume product with the base concentration-volume product.")
        }
    }

    private static func computedDataScienceTarget(_ index: Int) -> NFRetrievalKnowledgeTarget {
        let step = index % 10
        switch index / 10 {
        case 0:
            let first = step + 2
            let mean = first + 5
            return k("mean-\(first)-\(first + 5)-\(first + 10)", .dataScience, "descriptive-statistics-calculation",
                     "What is the arithmetic mean of the values \(first), \(first + 5), and \(first + 10)?",
                     "\(mean)", [],
                     "For three equally spaced observations, their arithmetic mean is the central observation.")
        case 1:
            let center = step + 10
            let values = [center - 5, center - 2, center, center + 3, center + 8]
            return k("median-five-\(center)", .dataScience, "descriptive-statistics-calculation",
                     "What is the median of the ordered values \(values.map(String.init).joined(separator: ", "))?",
                     "\(center)", [],
                     "With five ordered observations, the median is the third value in positional order.")
        case 2:
            let minimum = step + 3
            let maximum = minimum + 10 + step
            let range = maximum - minimum
            return k("range-\(minimum)-\(maximum)", .dataScience, "descriptive-statistics-calculation",
                     "What is the range of a data set whose minimum is \(minimum) and maximum is \(maximum)?",
                     "\(range)", [],
                     "Data range is calculated by subtracting the minimum observation from the maximum observation.")
        case 3:
            let mean = step + 20
            let deviation = step + 1
            let low = mean - deviation
            let high = mean + deviation
            let variance = deviation * deviation
            return k("population-variance-\(mean)-\(deviation)", .dataScience, "descriptive-statistics-calculation",
                     "Using the population formula, what is the variance of \(low), \(low), \(high), and \(high)?",
                     "\(variance)", [],
                     "All four observations lie one stated deviation from their mean, so every squared deviation is identical.")
        case 4:
            let z = step + 1
            let mean = 50
            let standardDeviation = step + 2
            let value = mean + z * standardDeviation
            return k("standard-score-\(value)-\(mean)-\(standardDeviation)", .dataScience, "standardization-calculation",
                     "A value is \(value), the mean is \(mean), and standard deviation is \(standardDeviation). What is the z-score?",
                     "\(z)", [],
                     "Subtracting the mean and dividing by standard deviation expresses the value in standard-deviation units.")
        case 5:
            let base = step + 1
            let errors = [base, -base, 2 * base, -2 * base]
            let mae = fixed(Double(6 * base) / 4, places: base % 2 == 0 ? 0 : 1)
            return k("mae-\(base)", .dataScience, "model-evaluation-calculation",
                     "What is the mean absolute error for signed errors \(errors.map(String.init).joined(separator: ", "))?",
                     mae, [],
                     "Taking absolute values prevents cancellation, and their sum divided by four gives mean absolute error.")
        case 6:
            let error = step + 1
            let mse = error * error
            return k("mse-uniform-\(error)", .dataScience, "model-evaluation-calculation",
                     "Four predictions have errors \(error), \(-error), \(error), and \(-error). What is their mean squared error?",
                     "\(mse)", [],
                     "Every squared error has the same value, so their arithmetic mean equals that common square.")
        case 7:
            let truePositives = 50 + 5 * step
            let falsePositives = 50 - 5 * step
            let precision = truePositives
            return k("precision-\(truePositives)-\(falsePositives)", .dataScience, "classification-calculation",
                     "A classifier has \(truePositives) true positives and \(falsePositives) false positives. Express the result as a percentage: what is its positive-class precision?",
                     "\(precision) percent", ["\(precision)%"],
                     "Precision divides true positives by all predicted positives, which include true and false positives.")
        case 8:
            let truePositives = 40 + 5 * step
            let falseNegatives = 60 - 5 * step
            let recall = truePositives
            return k("recall-\(truePositives)-\(falseNegatives)", .dataScience, "classification-calculation",
                     "A classifier has \(truePositives) true positives and \(falseNegatives) false negatives. Express the result as a percentage: what is its positive-class recall?",
                     "\(recall) percent", ["\(recall)%"],
                     "Recall divides true positives by all actual positives, including the missed false negatives.")
        default:
            let correct = 60 + 4 * step
            let incorrect = 100 - correct
            return k("accuracy-\(correct)-\(incorrect)", .dataScience, "classification-calculation",
                     "A classifier makes \(correct) correct and \(incorrect) incorrect predictions. Express the result as a percentage: what is its accuracy?",
                     "\(correct) percent", ["\(correct)%"],
                     "Accuracy divides the correct prediction count by all evaluated cases and expresses the result as percent.")
        }
    }

    static func target(id: String) -> NFRetrievalKnowledgeTarget? {
        targets.first { $0.id == id }
    }

    static func targets(for field: STEMField) -> [NFRetrievalKnowledgeTarget] {
        targets.filter { $0.field == field }
    }

    static func accepts(_ response: String, for target: NFRetrievalKnowledgeTarget) -> Bool {
        let normalizedResponse = normalized(response)
        guard !normalizedResponse.isEmpty else { return false }
        return target.allAcceptedAnswers.contains {
            normalized($0) == normalizedResponse
        }
    }

    static func normalized(_ value: String) -> String {
        let scalars = Array(
            value
                .folding(
                    options: [.caseInsensitive, .diacriticInsensitive],
                    locale: Locale(identifier: "en_US_POSIX")
                )
                .lowercased()
                .unicodeScalars
        )
        var tokens: [String] = []
        var word = ""
        var superscriptExponent = ""

        func flushWord() {
            guard !word.isEmpty else { return }
            tokens.append(word)
            word.removeAll(keepingCapacity: true)
        }

        func flushSuperscriptExponent() {
            guard !superscriptExponent.isEmpty else { return }
            tokens.append("^")
            if superscriptExponent.first == "+" || superscriptExponent.first == "-" {
                tokens.append(String(superscriptExponent.removeFirst()))
            }
            if !superscriptExponent.isEmpty {
                tokens.append(superscriptExponent)
            }
            superscriptExponent.removeAll(keepingCapacity: true)
        }

        for (index, scalar) in scalars.enumerated() {
            if let exponentCharacter = superscriptExponentCharacter(for: scalar) {
                flushWord()
                superscriptExponent.append(exponentCharacter)
                continue
            }
            flushSuperscriptExponent()
            if CharacterSet.alphanumerics.contains(scalar) {
                word.unicodeScalars.append(scalar)
                continue
            }

            flushWord()
            if scalar == ",", isStructuralGroupingComma(at: index, in: scalars) {
                tokens.append(",")
                continue
            }
            let previousSignificant = scalars[..<index].last {
                !CharacterSet.whitespacesAndNewlines.contains($0)
            }
            let nextSignificant = scalars[(index + 1)...].first {
                !CharacterSet.whitespacesAndNewlines.contains($0)
            }
            if let mathematicalToken = mathematicalToken(
                for: scalar,
                previous: previousSignificant,
                next: nextSignificant
            ) {
                tokens.append(mathematicalToken)
            }
        }
        flushSuperscriptExponent()
        flushWord()
        return tokens.joined(separator: " ")
    }

    static func audit() -> [String] {
        var violations: [String] = []
        if reviewedTargets.count != editorialTargetCount {
            violations.append("editorial-target-count:\(reviewedTargets.count)")
        }
        if computedTargets.count != computedTargetCount {
            violations.append("computed-target-count:\(computedTargets.count)")
        }
        if STEMField.allCases.count * 10 != computedFamilyCount {
            violations.append("computed-family-count:\(computedFamilyCount)")
        }
        if targets.count != requiredTotalCount {
            violations.append("target-count:\(targets.count)")
        }
        if Set(targets.map(\.id)).count != targets.count {
            violations.append("duplicate-id")
        }
        if Set(targets.map { normalized($0.prompt) }).count != targets.count {
            violations.append("duplicate-prompt")
        }
        if Set(targets.map(\.semanticIdentity)).count != targets.count {
            violations.append("duplicate-semantic-identity")
        }
        if normalized("¬A") == normalized("A") {
            violations.append("normalization-negation")
        }
        if normalized("2.0:1") == normalized("2.0 1") {
            violations.append("normalization-ratio")
        }
        if normalized("(2, 3)") == normalized("(2 3)") {
            violations.append("normalization-coordinate")
        }
        if normalized("((x1+x2)/2, (y1+y2)/2)")
            == normalized("((x1+x2)/2 (y1+y2)/2)") {
            violations.append("normalization-symbolic-tuple")
        }
        let superscriptEquivalences = [
            ("m²", "m^2"),
            ("m³", "m^3"),
            ("µm²", "µm^2"),
            ("µm³", "µm^3"),
            ("m⁻²", "m^-2"),
            ("m¹⁰", "m^10")
        ]
        for (superscript, caret) in superscriptEquivalences
        where normalized(superscript) != normalized(caret) {
            violations.append("normalization-superscript:\(caret)")
        }
        let twoMoleParticles = target(id: "nf.retrieval.v1.chemistry.particle-count-2")
        if twoMoleParticles?.answer != "1.2 × 10^24 particles"
            || twoMoleParticles.map({ accepts("12 × 10^23 particles", for: $0) }) != true {
            violations.append("particle-scientific-notation:2")
        }
        if target(id: "nf.retrieval.v1.chemistry.particle-count-10")?.answer
            != "6.0 × 10^24 particles" {
            violations.append("particle-scientific-notation:10")
        }
        if target(id: "nf.retrieval.v1.chemistry.particle-count-10")
            .map({ accepts("6 × 10^24 particles", for: $0) }) != true {
            violations.append("particle-compact-scientific-notation:10")
        }

        for field in STEMField.allCases {
            let fieldTargets = targets(for: field)
            if fieldTargets.count != requiredCountPerField {
                violations.append("field-count:\(field.rawValue):\(fieldTargets.count)")
            }
            if Set(fieldTargets.map(\.category)).count < 5 {
                violations.append("category-breadth:\(field.rawValue)")
            }
        }

        let permittedSlugCharacters = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789-.")
        for target in targets {
            // Record IDs retain their v1 namespace across catalog releases so
            // an already-seen knowledge target never appears novel solely
            // because the surrounding catalog version changed.
            let expectedPrefix = "nf.retrieval.v1.\(fieldToken(target.field))."
            if !target.id.hasPrefix(expectedPrefix)
                || target.id.unicodeScalars.contains(where: { !permittedSlugCharacters.contains($0) }) {
                violations.append("id:\(target.id)")
            }
            if target.category.isEmpty
                || target.prompt.split(whereSeparator: \.isWhitespace).count < 5
                || target.answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || target.explanation.split(whereSeparator: \.isWhitespace).count < 8 {
                violations.append("incomplete:\(target.id)")
            }
            if !target.prompt.hasSuffix("?") {
                violations.append("prompt-punctuation:\(target.id)")
            }
            let normalizedAnswers = target.allAcceptedAnswers.map(normalized)
            if normalizedAnswers.contains(where: \.isEmpty)
                || Set(normalizedAnswers).count != normalizedAnswers.count {
                violations.append("answers:\(target.id)")
            }
            if !accepts(target.answer, for: target) {
                violations.append("canonical-answer:\(target.id)")
            }
        }
        return Array(Set(violations)).sorted()
    }

    private static func k(
        _ slug: String,
        _ field: STEMField,
        _ category: String,
        _ prompt: String,
        _ answer: String,
        _ alternatives: [String],
        _ explanation: String
    ) -> NFRetrievalKnowledgeTarget {
        NFRetrievalKnowledgeTarget(
            id: "nf.retrieval.v1.\(fieldToken(field)).\(slug)",
            field: field,
            category: category,
            prompt: prompt,
            answer: answer,
            acceptedAnswers: alternatives,
            explanation: explanation
        )
    }

    private static func fieldToken(_ field: STEMField) -> String {
        switch field {
        case .general: "general"
        case .mathematics: "mathematics"
        case .physics: "physics"
        case .computing: "computing"
        case .engineering: "engineering"
        case .lifeSciences: "life-sciences"
        case .chemistry: "chemistry"
        case .dataScience: "data-science"
        }
    }

    private static func fixed(_ value: Double, places: Int) -> String {
        String(
            format: "%.\(places)f",
            locale: Locale(identifier: "en_US_POSIX"),
            value
        )
    }

    /// Produces an exact, locale-stable spelling alternative when fixed-width
    /// output contains insignificant trailing zeroes. Canonical answers retain
    /// their reviewed display precision; this is deliberately not part of the
    /// global answer normalizer.
    private static func compactPOSIXDecimal(_ value: String) -> String {
        guard value.contains(".") else { return value }
        var compact = value
        while compact.last == "0" {
            compact.removeLast()
        }
        if compact.last == "." {
            compact.removeLast()
        }
        return compact
    }

    private static func superscriptExponentCharacter(
        for scalar: UnicodeScalar
    ) -> Character? {
        switch scalar {
        case "⁰": "0"
        case "¹": "1"
        case "²": "2"
        case "³": "3"
        case "⁴": "4"
        case "⁵": "5"
        case "⁶": "6"
        case "⁷": "7"
        case "⁸": "8"
        case "⁹": "9"
        case "⁺": "+"
        case "⁻": "-"
        default: nil
        }
    }

    private static func dnaComplement(_ sequence: String) -> String {
        String(sequence.map { base in
            switch base {
            case "A": "T"
            case "T": "A"
            case "C": "G"
            case "G": "C"
            default:
                preconditionFailure("Unsupported DNA base in bundled retrieval target")
            }
        })
    }

    private static func isStructuralGroupingComma(
        at index: Int,
        in scalars: [UnicodeScalar]
    ) -> Bool {
        let opening: Set<UnicodeScalar> = ["(", "[", "{"]
        let closing: Set<UnicodeScalar> = [")", "]", "}"]
        var stack: [(scalar: UnicodeScalar, index: Int)] = []
        for cursor in 0..<index {
            let scalar = scalars[cursor]
            if opening.contains(scalar) {
                stack.append((scalar, cursor))
            } else if closing.contains(scalar), !stack.isEmpty {
                stack.removeLast()
            }
        }
        guard let enclosing = stack.last else { return false }
        let enclosingDepth = stack.count

        var componentStart = enclosing.index + 1
        var depth = enclosingDepth
        if componentStart < index {
            for cursor in componentStart..<index {
                let scalar = scalars[cursor]
                if opening.contains(scalar) {
                    depth += 1
                } else if closing.contains(scalar) {
                    depth -= 1
                } else if scalar == ",", depth == enclosingDepth {
                    componentStart = cursor + 1
                }
            }
        }

        var componentEnd: Int?
        depth = enclosingDepth
        if index + 1 < scalars.count {
            for cursor in (index + 1)..<scalars.count {
                let scalar = scalars[cursor]
                if opening.contains(scalar) {
                    depth += 1
                } else if closing.contains(scalar) {
                    if depth == enclosingDepth {
                        componentEnd = cursor
                        break
                    }
                    depth -= 1
                } else if scalar == ",", depth == enclosingDepth {
                    componentEnd = cursor
                    break
                }
            }
        }
        guard let componentEnd else { return false }
        return isCompactMathematicalComponent(scalars[componentStart..<index])
            && isCompactMathematicalComponent(scalars[(index + 1)..<componentEnd])
    }

    private static func isCompactMathematicalComponent(
        _ component: ArraySlice<UnicodeScalar>
    ) -> Bool {
        let trimmed = component.drop(while: CharacterSet.whitespacesAndNewlines.contains)
            .reversed()
            .drop(while: CharacterSet.whitespacesAndNewlines.contains)
            .reversed()
        guard !trimmed.isEmpty else { return false }

        let permittedSymbols = CharacterSet(charactersIn: "+-*/^=._()[]{}")
        guard trimmed.allSatisfy({
            CharacterSet.alphanumerics.contains($0)
                || CharacterSet.whitespacesAndNewlines.contains($0)
                || permittedSymbols.contains($0)
        }) else {
            return false
        }

        let values = Array(trimmed)
        for cursor in values.indices where CharacterSet.whitespacesAndNewlines.contains(values[cursor]) {
            let previous = values[..<cursor].last {
                !CharacterSet.whitespacesAndNewlines.contains($0)
            }
            let next = values[(cursor + 1)...].first {
                !CharacterSet.whitespacesAndNewlines.contains($0)
            }
            if previous.map(CharacterSet.alphanumerics.contains) == true,
               next.map(CharacterSet.alphanumerics.contains) == true {
                return false
            }
        }

        if values.contains(where: CharacterSet.decimalDigits.contains)
            || values.contains(where: permittedSymbols.contains) {
            return true
        }
        return values.filter(CharacterSet.alphanumerics.contains).count <= 2
    }

    /// Returns symbols whose removal could change a mathematical or scientific
    /// assertion. Sentence punctuation is intentionally ignored, while signs,
    /// operators, grouping, subscripts, percentages, and decimal points survive.
    private static func mathematicalToken(
        for scalar: UnicodeScalar,
        previous: UnicodeScalar?,
        next: UnicodeScalar?
    ) -> String? {
        switch scalar {
        case "+", "-", "*", "/", "^", "=", "<", ">", "%",
             "(", ")", "[", "]", "{", "}", "_", "°", "±", "¬":
            String(scalar)
        case "−", "–", "—":
            "-"
        case "×", "·", "⋅":
            "*"
        case "÷":
            "/"
        case "≤":
            "<="
        case "≥":
            ">="
        case "≠":
            "!="
        case ":":
            if previous.map(CharacterSet.decimalDigits.contains) == true,
               next.map(CharacterSet.decimalDigits.contains) == true {
                ":"
            } else {
                nil
            }
        case ".":
            if previous.map(CharacterSet.decimalDigits.contains) == true,
               next.map(CharacterSet.decimalDigits.contains) == true {
                "."
            } else {
                nil
            }
        default:
            nil
        }
    }
}
