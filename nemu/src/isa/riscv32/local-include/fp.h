#ifndef __RISCV32_FP_H__
#define __RISCV32_FP_H__

#include <common.h>

enum {
  FP_CSR_FFLAGS = 0x001,
  FP_CSR_FRM    = 0x002,
  FP_CSR_FCSR   = 0x003,
};

typedef enum {
  FP_BIN_ADD,
  FP_BIN_SUB,
  FP_BIN_MUL,
  FP_BIN_DIV,
} fp_binary_op_t;

typedef enum {
  FP_SGNJ_COPY,
  FP_SGNJ_NEGATE,
  FP_SGNJ_XOR,
} fp_sgnj_op_t;

typedef enum {
  FP_CMP_EQ,
  FP_CMP_LT,
  FP_CMP_LE,
} fp_compare_op_t;

void fp_init(void);
word_t fp_normalize_mstatus(word_t value);
word_t fp_csr_read(uint32_t addr);
void fp_csr_write(uint32_t addr, word_t value);

void fp_load_s(int rd, vaddr_t addr);
void fp_store_s(int rs2, vaddr_t addr);
void fp_load_d(int rd, vaddr_t addr);
void fp_store_d(int rs2, vaddr_t addr);

void fp_binary_s(int rd, int rs1, int rs2, uint32_t rm, fp_binary_op_t op);
void fp_binary_d(int rd, int rs1, int rs2, uint32_t rm, fp_binary_op_t op);
void fp_sqrt_s(int rd, int rs1, uint32_t rm);
void fp_sqrt_d(int rd, int rs1, uint32_t rm);
void fp_fma_s(int rd, int rs1, int rs2, int rs3, uint32_t rm,
    bool negate_product, bool negate_addend);
void fp_fma_d(int rd, int rs1, int rs2, int rs3, uint32_t rm,
    bool negate_product, bool negate_addend);
void fp_sgnj_s(int rd, int rs1, int rs2, fp_sgnj_op_t op);
void fp_sgnj_d(int rd, int rs1, int rs2, fp_sgnj_op_t op);
void fp_minmax_s(int rd, int rs1, int rs2, bool is_max);
void fp_minmax_d(int rd, int rs1, int rs2, bool is_max);

word_t fp_compare_s(int rs1, int rs2, fp_compare_op_t op);
word_t fp_compare_d(int rs1, int rs2, fp_compare_op_t op);
word_t fp_classify_s(int rs1);
word_t fp_classify_d(int rs1);
word_t fp_move_x_w(int rs1);
void fp_move_w_x(int rd, word_t value);

word_t fp_to_i_s(int rs1, uint32_t rm, bool is_unsigned);
word_t fp_to_i_d(int rs1, uint32_t rm, bool is_unsigned);
void fp_from_i_s(int rd, word_t value, uint32_t rm, bool is_unsigned);
void fp_from_i_d(int rd, word_t value, uint32_t rm, bool is_unsigned);
void fp_convert_s_d(int rd, int rs1, uint32_t rm);
void fp_convert_d_s(int rd, int rs1, uint32_t rm);

#endif
