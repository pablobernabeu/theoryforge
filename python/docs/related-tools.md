# Related tools

theoryforge sits among tools for causal graphs, structural equation modelling, bibliometrics, preregistration and the specification of theories. This page says what each neighbour does, what theoryforge adds or lacks beside it and how a theory moves between them. The routes that run through another package were tried with the versions named. Where a route loses information, the page says what is lost and, where there is one, gives a route that keeps it.

theoryforge appraises one versioned theory object, through the rigour checklist, the causal reading of its propositions, riskiness and post-data severity, the amendment appraisal and the placing of the theory and its rivals in a literature. It does not estimate models from data, learn causal graphs, test implied independencies against data, archive theories with a DOI or fill in registered preregistration templates, and the tools below do one or more of these.

## Theory specification: FAIR theory and theorytools

Van Lissa et al. (2026) propose that theories be made findable, accessible, interoperable and reusable. A FAIR theory lives in a Git repository with a file that states the theory, a README and a licence, and is released to Zenodo with a DOI. The R package [theorytools](https://cran.r-project.org/package=theorytools) (version 0.1.3) automates this with `create_fair_theory()`, which writes the repository and its Zenodo metadata, and `download_theory()`, which retrieves one. It also selects control variables and filters implied independencies through dagitty, derives regression formulas and simulates data from DAGs whose edges carry functional forms, and compares definitions by string distance or embeddings.

The two packages overlap in versioned specification, implied independencies and the comparison of construct definitions. theorytools prepares a theory for release on Zenodo, which gives it a DOI, and simulates data from it. theoryforge's nearest route is `osf_push()`, which uploads the theory's dossier, and not the theory file, to an OSF project's storage. That upload is not a registration, and it gives the file no DOI of its own. theoryforge holds predictions, auxiliary assumptions, rivals and test outcomes in a validated schema, and adds the checklist, the causal reading of claims, the amendment appraisal and the literature layer, which theorytools does not.

A FAIR theory whose formal file is DAGitty code reads into theoryforge with `read_dagitty()`, as the self-determination theory example that theorytools ships does. Its definitions sit in a separate table and have to be added to the constructs before the theory validates. A prose operationalisation belongs in a construct's `measurement` only when it can serve as an indicator name, since `compile_sem()` turns each entry into a variable name. In the other direction, the `causal_dag` view of `diagram()` writes the theory's graph as DAGitty code that a FAIR repository can hold. theorytools is licensed under the GPL and theoryforge under MIT, so the two meet through files and share no code.

## Causal graphs: DAGitty, ggdag, pgmpy, DoWhy and y0

[DAGitty](https://www.dagitty.net/) is a browser editor for causal diagrams (Textor et al., 2011), and the R package dagitty (Textor et al., 2016; version 0.3-4) analyses the same model code. It lists implied conditional independencies, tests them against data with `localTests()` (Ankan et al., 2021), finds adjustment sets and instrumental variables, and gives the equivalence class of a graph. theoryforge writes its graph as DAGitty code through the `causal_dag` view and reads DAGitty code with `read_dagitty()`, so a diagram drawn in DAGitty can start a theory and a theory's graph can be opened in DAGitty. The export carries no positions, so DAGitty lays the graph out afresh.

```python exec="1" source="block" result="text" session="related"
import theoryforge as tf

M = tf.read(tf.example_path("modality-switching.theory.yaml"))
code = tf.diagram(M, "causal_dag")
print(code)
back = tf.read_dagitty(code)
for p in back.data["propositions"]:
    print(p["from"], p["relation"], p["to"])
```

The round trip keeps the graph and loses what DAGitty code cannot hold: the definitions, the measures, the mechanisms and the sign of each relation. Every edge comes back as `causes` unless the `relation` argument gives all of them one sign.

The two tools also read a graph differently. By default, theoryforge conditions each implied independence on the parents of both constructs, which gives Shipley's (2000) basis set, where DAGitty's default chooses smaller sets, and `given="minimal"` prunes theoryforge's sets to minimal ones. DAGitty reads a graph with a feedback loop by d-separation without a warning, while theoryforge refuses such a graph by default and reads it by sigma-separation on request (Bongers et al., 2021).

One route out of theoryforge reverses the theory's meaning. dagitty's `lavaanToGraph()` reads the zero-covariance lines that `compile_sem()` writes, such as `c_switch_cost ~~ 0*c_conceptual_access`, as bidirected edges, which assert the covariance the line rules out. Pass dagitty the `causal_dag` view and not the lavaan syntax.

[ggdag](https://cran.r-project.org/package=ggdag) draws, with ggplot2, graphs that dagitty has read, so the `causal_dag` view reaches it through `dagitty::dagitty()`. theoryforge's own diagram views draw the same structure as Graphviz DOT, without ggplot2.

[pgmpy](https://pypi.org/project/pgmpy/) (Ankan & Panda, 2015; version 1.1.2) is a Python library for graphical models. `DAG.from_dagitty()` reads the `causal_dag` view of an acyclic theory, turns each association into a latent common cause named `u_<a>_<b>` and refuses a graph with a feedback loop. Its `metrics` module tests the implied independencies of a graph against data, among other ways by Shipley's C (`fisher_c()`), a step that theoryforge leaves to such tools. The lavaan route into pgmpy does not work. `DAG.from_lavaan()` skips, without a warning, every line whose names contain an underscore, so the output of `compile_sem()`, whose names all contain one, reads as an empty graph. Use `from_dagitty()` instead.

[DoWhy](https://pypi.org/project/dowhy/) (version 0.14) estimates causal effects from data in four steps: modelling, identification, estimation and refutation. Its `gcm` module tests a graph's local Markov conditions against data. It accepts a graph as a networkx object, as DOT or as DAGitty code, but DAGitty code loses its associations there. Whether the `causal_dag` view is passed to `CausalModel` directly or through DoWhy's converter, each bidirected line becomes a variable named `<->` and no edge, without an error. In an example theory of planned behaviour, the adjustment set DoWhy then finds for the effect of attitude on behaviour is empty, where the theory's associations call for adjusting for subjective norm and perceived control. Pass DoWhy a networkx graph in which each association is a latent common cause, such as the graph pgmpy's `from_dagitty()` returns, and DoWhy then finds that adjustment set.

[y0](https://pypi.org/project/y0/) (version 0.2.11) identifies causal effects on mixed graphs, including counterfactual and transport queries that theoryforge does not address, and it offers a sigma-separation test. That test gives a wrong answer on a small graph. For A → B, B → C, C → B and D → C, `are_sigma_separated()` reports that A and D are not sigma-separated, although every path between them passes through a collider that nothing holds fixed. `implications(cycles="sigma")` gives `A _||_ D` for the same graph. A theory moves to y0 by building its `NxMixedGraph` from the directed edges and the associations of the `causal_dag` view.

## Structural equation models: lavaan and semopy

`compile_sem()` writes a theory as model syntax for [lavaan](https://cran.r-project.org/package=lavaan) (Rosseel, 2012). The syntax holds a measurement model from each construct's `measurement`, a labelled regression for each path, a covariance for each association and, as comments, the sign each `increases` or `decreases` proposition states. It defines with `:=` the effect that each effect claim is about, and fixes at zero the covariances the graph rules out, which `lavaan::sem()` would otherwise free. The indicator names are the sanitised measurement entries and must match the columns of the data. Fitting the model, checking its identification and reading its estimates are left to lavaan, and the estimate and standard error of a defined effect can be recorded in a test outcome, where `post_data_severity()` reads them.

[semopy](https://pypi.org/project/semopy/) (Igolkina & Meshcheryakov, 2020; version 2.3.11) fits lavaan-like syntax in Python. It refuses the `:=` lines of `compile_sem()`, which therefore have to be deleted first. It then reads the rest, labels included, and keeps the fixed covariances at zero. The syntax assumes the defaults of `lavaan::sem()` for the covariances it does not write, so check the covariances semopy frees against those the theory intends.

## Bibliometrics: bibliometrix and openalexR

[bibliometrix](https://cran.r-project.org/package=bibliometrix) (Aria & Cuccurullo, 2017) is a suite for mapping a scientific field. It reads exports from Web of Science, Scopus, OpenAlex and other databases, draws co-occurrence, co-citation and thematic maps and follows themes over time, with the biblioshiny app as its interface. Its `thematicMap()` and `litmap(method="simple_centres")` both place themes in a strategic diagram by centrality and density (Callon et al., 1991). They cluster the keywords differently, and bibliometrix places the themes by the ranks of the two measures, so their values are not comparable. theoryforge's map is narrower and adds `landscape()`, which places a theory and its registered rivals among the themes. A corpus moves from bibliometrix to theoryforge by writing each record's title, year, DOI, keywords and cited references in the corpus schema.

[openalexR](https://cran.r-project.org/package=openalexR) (Aria et al., 2024) is an R client for OpenAlex, with its full filter syntax, citation chasing (`oa_snowball()`) and retries. `fetch_corpus()` meets a narrower need, turning an OpenAlex search into a theoryforge corpus with the same records in R and Python. For anything beyond a search, fetch the records with openalexR and write them in the corpus schema.

## Hypotheses and preregistration: scienceverse, preregr and TOSTER

[scienceverse](https://github.com/scienceverse/scienceverse), an R package on GitHub, describes a study in machine-readable form. Each hypothesis is stated as criteria on the results of an analysis, with conditions for corroboration and for falsification that the package evaluates (Lakens & DeBruine, 2021). theoryforge records whether a test passed and leaves the criteria that decide it to the author, and scienceverse holds no theory, propositions or rivals from which a hypothesis is derived. The two complement each other, theoryforge for the theory and the derivation of its predictions and scienceverse for the criteria and their evaluation, and neither package converts the other's records.

[preregr](https://cran.r-project.org/package=preregr), archived from CRAN in July 2026, specifies a preregistration as a structured object, with form definitions such as PRP-QUANT, and exports it as HTML or PDF for readers and as JSON or YAML for machines. `preregister()` writes the theory and hypotheses sections of a preregistration from the theory, in its own layout and in no registered template, so its content is copied into the form that a registry or a journal asks for.

[TOSTER](https://cran.r-project.org/package=TOSTER) runs equivalence tests (Lakens, 2017), in t-based, bootstrap and nonparametric variants, and computes power for planning them. For a claim with two finite bounds, `post_data_severity()` equals 1 minus the p value of the z-based two one-sided tests, which TOSTER's `TOSTmeta()` computes from an estimate and its standard error. TOSTER's t-based tests suit small samples, in which the normal approximation of `post_data_severity()` overstates the severity of an estimate inside the region, and its power functions can check a sampling plan that theoryforge records but does not recompute.

## Arguments and formal models: VAST and PsychoModels

The Visual Argument Structure Tool (VAST; Leising et al., 2023) visualises the relations that make up an argument. It keeps concepts apart from the names used for them, and it gives causation, conceptual implication, prediction, transformation and reasoning each a relation of its own, apart from beliefs about what is or ought to be the case. theoryforge's propositions hold causal relations and associations only, so a definitional or part-whole relation that VAST states has no counterpart, and a VAST diagram has to be reduced to its causal relations before it can be written as a theory.

The PsychoModels database (Nak et al., 2025) is an online repository that stores, indexes and describes the mathematical and computational models of psychology by the FAIR principles. A theory whose formal model is a system of differential equations or an agent-based model can point to such a model through the `spec_ref` of its `formal_model`, and theoryforge then checks the verbal and causal structure around the model. theoryforge has no converter for VAST or PsychoModels.

## References

<p style="margin: 0 0 0.6em 0; padding-left: 1.8em; text-indent: -1.8em;">Ankan, A., &amp; Panda, A. (2015). pgmpy: Probabilistic graphical models using Python. In <em>Proceedings of the 14th Python in Science Conference</em> (pp. 6–11). SciPy. <a href="https://doi.org/10.25080/Majora-7b98e3ed-001">https://doi.org/10.25080/Majora-7b98e3ed-001</a></p>

<p style="margin: 0 0 0.6em 0; padding-left: 1.8em; text-indent: -1.8em;">Ankan, A., Wortel, I. M. N., &amp; Textor, J. (2021). Testing graphical causal models using the R package “dagitty”. <em>Current Protocols</em>, <em>1</em>(2), Article e45. <a href="https://doi.org/10.1002/cpz1.45">https://doi.org/10.1002/cpz1.45</a></p>

<p style="margin: 0 0 0.6em 0; padding-left: 1.8em; text-indent: -1.8em;">Aria, M., &amp; Cuccurullo, C. (2017). bibliometrix: An R-tool for comprehensive science mapping analysis. <em>Journal of Informetrics</em>, <em>11</em>(4), 959–975. <a href="https://doi.org/10.1016/j.joi.2017.08.007">https://doi.org/10.1016/j.joi.2017.08.007</a></p>

<p style="margin: 0 0 0.6em 0; padding-left: 1.8em; text-indent: -1.8em;">Aria, M., Le, T., Cuccurullo, C., Belfiore, A., &amp; Choe, J. (2024). openalexR: An R-tool for collecting bibliometric data from OpenAlex. <em>The R Journal</em>, <em>15</em>(4), 167–180. <a href="https://doi.org/10.32614/RJ-2023-089">https://doi.org/10.32614/RJ-2023-089</a></p>

<p style="margin: 0 0 0.6em 0; padding-left: 1.8em; text-indent: -1.8em;">Bongers, S., Forré, P., Peters, J., &amp; Mooij, J. M. (2021). Foundations of structural causal models with cycles and latent variables. <em>The Annals of Statistics</em>, <em>49</em>(5), 2885–2915. <a href="https://doi.org/10.1214/21-AOS2064">https://doi.org/10.1214/21-AOS2064</a></p>

<p style="margin: 0 0 0.6em 0; padding-left: 1.8em; text-indent: -1.8em;">Callon, M., Courtial, J. P., &amp; Laville, F. (1991). Co-word analysis as a tool for describing the network of interactions between basic and technological research: The case of polymer chemistry. <em>Scientometrics</em>, <em>22</em>(1), 155–205. <a href="https://doi.org/10.1007/BF02019280">https://doi.org/10.1007/BF02019280</a></p>

<p style="margin: 0 0 0.6em 0; padding-left: 1.8em; text-indent: -1.8em;">Igolkina, A. A., &amp; Meshcheryakov, G. (2020). semopy: A Python package for structural equation modeling. <em>Structural Equation Modeling: A Multidisciplinary Journal</em>, <em>27</em>(6), 952–963. <a href="https://doi.org/10.1080/10705511.2019.1704289">https://doi.org/10.1080/10705511.2019.1704289</a></p>

<p style="margin: 0 0 0.6em 0; padding-left: 1.8em; text-indent: -1.8em;">Lakens, D. (2017). Equivalence tests: A practical primer for <em>t</em> tests, correlations, and meta-analyses. <em>Social Psychological and Personality Science</em>, <em>8</em>(4), 355–362. <a href="https://doi.org/10.1177/1948550617697177">https://doi.org/10.1177/1948550617697177</a></p>

<p style="margin: 0 0 0.6em 0; padding-left: 1.8em; text-indent: -1.8em;">Lakens, D., &amp; DeBruine, L. M. (2021). Improving transparency, falsifiability, and rigor by making hypothesis tests machine-readable. <em>Advances in Methods and Practices in Psychological Science</em>, <em>4</em>(2), Article 2515245920970949. <a href="https://doi.org/10.1177/2515245920970949">https://doi.org/10.1177/2515245920970949</a></p>

<p style="margin: 0 0 0.6em 0; padding-left: 1.8em; text-indent: -1.8em;">Leising, D., Grenke, O., &amp; Cramer, M. (2023). Visual Argument Structure Tool (VAST) Version 1.0. <em>Meta-Psychology</em>, <em>7</em>. <a href="https://doi.org/10.15626/MP.2021.2911">https://doi.org/10.15626/MP.2021.2911</a></p>

<p style="margin: 0 0 0.6em 0; padding-left: 1.8em; text-indent: -1.8em;">Nak, J., Volz, L., Verbrugh, V., Borsboom, D., &amp; van Dongen, N. (2025). The PsychoModels database – Facilitating the exchange of formal models. <em>Zeitschrift für Psychologie</em>, <em>233</em>(4), 271–278. <a href="https://doi.org/10.1027/2151-2604/a000601">https://doi.org/10.1027/2151-2604/a000601</a></p>

<p style="margin: 0 0 0.6em 0; padding-left: 1.8em; text-indent: -1.8em;">Rosseel, Y. (2012). lavaan: An R package for structural equation modeling. <em>Journal of Statistical Software</em>, <em>48</em>(2), 1–36. <a href="https://doi.org/10.18637/jss.v048.i02">https://doi.org/10.18637/jss.v048.i02</a></p>

<p style="margin: 0 0 0.6em 0; padding-left: 1.8em; text-indent: -1.8em;">Shipley, B. (2000). A new inferential test for path models based on directed acyclic graphs. <em>Structural Equation Modeling: A Multidisciplinary Journal</em>, <em>7</em>(2), 206–218. <a href="https://doi.org/10.1207/S15328007SEM0702_4">https://doi.org/10.1207/S15328007SEM0702_4</a></p>

<p style="margin: 0 0 0.6em 0; padding-left: 1.8em; text-indent: -1.8em;">Textor, J., Hardt, J., &amp; Knüppel, S. (2011). DAGitty: A graphical tool for analyzing causal diagrams. <em>Epidemiology</em>, <em>22</em>(5), 745. <a href="https://doi.org/10.1097/EDE.0b013e318225c2be">https://doi.org/10.1097/EDE.0b013e318225c2be</a></p>

<p style="margin: 0 0 0.6em 0; padding-left: 1.8em; text-indent: -1.8em;">Textor, J., van der Zander, B., Gilthorpe, M. S., Liśkiewicz, M., &amp; Ellison, G. T. H. (2016). Robust causal inference using directed acyclic graphs: The R package ‘dagitty’. <em>International Journal of Epidemiology</em>, <em>45</em>(6), 1887–1894. <a href="https://doi.org/10.1093/ije/dyw341">https://doi.org/10.1093/ije/dyw341</a></p>

<p style="margin: 0 0 0.6em 0; padding-left: 1.8em; text-indent: -1.8em;">Van Lissa, C. J., Peikert, A., Ernst, M. S., van Dongen, N. N. N., Schönbrodt, F. D., &amp; Brandmaier, A. M. (2026). To be FAIR: Theory specification needs an update. <em>Perspectives on Psychological Science</em>, <em>21</em>(2), 173–191. <a href="https://doi.org/10.1177/17456916251401850">https://doi.org/10.1177/17456916251401850</a></p>
