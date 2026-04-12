// Copyright 2020 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51

`ifndef SNITCH_ACC_INTERFACE_SVH
`define SNITCH_ACC_INTERFACE_SVH

package snitch_acc_pkg;
  import snitch_pkg::*;

  typedef struct packed {
    acc_addr_e   addr;
    logic [4:0]  id;
    logic [31:0] data_op;
    data_t       data_arga;
    data_t       data_argb;
    addr_t       data_argc;
  } acc_req_t;

  typedef struct packed {
    logic [4:0] id;
    logic       error;
    data_t      data;
  } acc_resp_t;

endpackage

`endif // SNITCH_ACC_INTERFACE_SVH
