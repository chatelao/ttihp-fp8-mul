# System Circuit Diagram

The **OCP MXFP8 Streaming MAC Unit** is implemented as a 32-element streaming Multiply-Accumulate unit. It processes 8-bit inputs (`ui_in` and `uio_in`) to compute a 32-bit dot product, which is then serialized to the 8-bit output (`uo_out`).

## Circuitikz Representation

The following diagram illustrates the top-level module interface and the primary internal functional blocks.

```math
    % Module Boundary
    \draw[thick] (0,0) rectangle (10,8);
    \node[anchor=north] at (5,7.8) {\large \textbf{tt\_um\_chatelao\_fp8\_multiplier}};

    % Input Ports (LHS)
    \draw (-1,6.5) node[anchor=east] {ui\_in[7:0]} -- (0,6.5);
    \draw (-1,5.5) node[anchor=east] {uio\_in[7:0]} -- (0,5.5);
    \draw (-1,3.5) node[anchor=east] {clk} -- (0,3.5);
    \draw (-1,2.5) node[anchor=east] {rst\_n} -- (0,2.5);
    \draw (-1,1.5) node[anchor=east] {ena} -- (0,1.5);

    % Functional Blocks
    \draw (1,4.5) rectangle (3,7.5) node[midway, align=center] {FSM \&\\Control\\Logic};
    \draw (4,5) rectangle (6,7) node[midway, align=center] {Dual\\Multiplier\\Lanes};
    \draw (7,5) rectangle (9,7) node[midway, align=center] {Dual\\Aligner\\Stage};
    \draw (7,1) rectangle (9,3) node[midway, align=center] {32-bit\\Accumulator\\\& Serializer};

    % Connections
    % Data paths
    \draw[->, thick] (3,6) -- (4,6); % FSM to Multiplier
    \draw[->, thick] (6,6) -- (7,6); % Multiplier to Aligner
    \draw[->, thick] (8,5) -- (8,3); % Aligner to Accumulator

    % Input to FSM/Mul
    \draw[->] (0.5,6.5) |- (1,6);
    \draw[->] (0.5,5.5) |- (1,5);

    % Control lines from FSM
    \draw[->, dashed] (2,4.5) |- (5,4) -- (5,5); % FSM to Multiplier control
    \draw[->, dashed] (2,4.5) |- (8,4) -- (8,5); % FSM to Aligner control
    \draw[->, dashed] (2,4.5) |- (7,2);           % FSM to Accumulator control

    % Output Ports (RHS)
    \draw (9,2) -- (11,2) node[anchor=west] {uo\_out[7:0]};

    % Legend
    \draw[dashed] (0.5,0.5) rectangle (4,2.5);
    \node[anchor=west] at (0.6,2.2) {\small \textbf{Legend:}};
    \draw[thick] (0.8,1.7) -- (1.5,1.7) node[right] {\scriptsize Data Path};
    \draw[dashed] (0.8,1.2) -- (1.5,1.2) node[right] {\scriptsize Control Path};
```

## Architectural Components

1.  **FSM & Control Logic**: Orchestrates the 41-cycle protocol, captures metadata in Cycle 0, and manages scale loading in Cycles 1-2.
2.  **Dual Multiplier Lanes**: Parallel 8-bit multipliers supporting OCP MX formats (E4M3, E5M2, etc.) and Mitchell's LNS approximation.
3.  **Dual Aligner Stage**: Performs per-element scaling and aligns products to a common 40-bit fixed-point grid.
4.  **32-bit Accumulator & Serializer**: Sums 32 products and serializes the final result for transmission over the 8-bit output port.
