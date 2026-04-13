# ROAD-SAFETY — AGENTS.md

## Mission

This repository is for the university project ROAD-SAFETY.

The project goal is to build a risk-aware urban routing system. The final target is not just descriptive analysis, but a technical pipeline that can eventually support:
- integrated accident/context data,
- a road-segment risk logic,
- graph edge weighting,
- and routing/API outputs.

All work must stay connected to that end goal.

## Current project focus

Current focus is exploratory statistical analysis in R, executed from Visual Studio Code, to support the design of the future risk index.

The immediate objective is to study redundancy and overlap among contextual/numeric variables, especially to avoid double-counting when the final risk score is designed.

PCA is being used as an exploratory tool, not as the final risk model and not as a causal model.

## Important methodological rules

- Do not treat the raw dataset as if one row always equals one accident.
- The correct accident-level unit is the expediente / accident identifier (for example `num_expediente`).
- Exact duplicate rows exist and must be considered before serious analysis.
- Many analyses should be performed on a deduplicated, accident-level table, not on the raw row-level dataset.
- Be careful with historical comparisons across old vs recent years because coding/schema may have changed around 2019.
- `vmed` is known to be noisy / dirty and should not be trusted blindly.
- `intensidad` and `ocupacion` are currently more promising.
- Categorical labels may require normalization before analysis.

## Environment and execution rules

- The user works in Visual Studio Code on Windows.
- R code is executed in an R terminal or via `Rscript.exe`.
- Do not assume RStudio.
- Prefer `.R` scripts unless the user explicitly asks for `.Rmd`.
- If a PowerShell error appears while trying to run R logic, first check whether the command is being executed in the wrong terminal.
- Use reproducible file paths and avoid brittle absolute paths when possible.
- Do not introduce unnecessary dependencies.

## Analysis rules

When working on exploratory analysis:
- explain the analytical purpose in terms of the ROAD-SAFETY system,
- distinguish clearly between exploratory findings and final design decisions,
- avoid causal language unless justified,
- avoid throwing all variables into one model without methodological justification,
- do not force categorical IDs or labels into PCA as fake numeric inputs,
- document data cleaning assumptions explicitly.

For the current PCA-related work:
- prefer a conservative variable set,
- prioritize interpretable numeric/contextual variables,
- scale variables when needed,
- treat binary variables carefully,
- and interpret components as latent structure / redundancy signals, not as “the true risk”.

## Working style

For any non-trivial task:
1. Start by summarizing the objective in technical terms.
2. List the files you plan to read or modify.
3. State assumptions and possible risks.
4. If the task is multi-step or architectural, create a plan first.
5. Only then implement.

When implementing:
- make the smallest sensible change set,
- keep code readable and modular,
- do not refactor unrelated parts,
- preserve working code unless a change is justified,
- prefer explicit validation over hand-wavy claims.

After implementation:
- say exactly what changed,
- say what was validated,
- say what remains uncertain.

## Validation rules

For R analysis tasks, validation should usually include some of:
- checking dimensions and column names,
- checking missing values,
- checking duplicate logic,
- checking accident-level aggregation,
- verifying transformations,
- printing interpretable summaries,
- and, if relevant, generating plots or PCA outputs that can actually be inspected.

Do not claim an analysis is complete if it only loads packages or reads a file.

## Planning rule for long tasks

For long or multi-step work, use `PLANS.md`.

Examples:
- building a full cleaning pipeline,
- redesigning repository structure,
- implementing graph preparation code,
- building the first API skeleton,
- or creating a full accident-to-segment risk pipeline.

In such cases:
- write the plan first,
- break work into milestones,
- define validation for each milestone,
- and do not silently jump to implementation of everything at once.

## Communication style

- Be concrete.
- Be technically rigorous.
- Stay connected to the project goal.
- Do not answer as if this were a generic stats exercise.
- Do not start from zero each time.