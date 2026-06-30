#include <assert.h>
#include <regex.h>
#include <stdlib.h>
#include <string.h>

#include "common.h"
#include "cpu/cpu.h"
#include "monitor/sdb.h"
#include "platform/platform.h"

#define MAX_TOKENS 65536
#define TOKEN_STR_SIZE 32

enum {
  TK_NOTYPE = 256, TK_HEX, TK_DEC, TK_REG,
  TK_EQ, TK_NEQ, TK_AND, TK_OR, TK_NOT, TK_LE, TK_GE, TK_SHL, TK_SHR,
  TK_NEG, TK_DEREF,
};

static struct rule {
  const char *regex;
  int token_type;
} rules[] = {
  {" +", TK_NOTYPE},
  {"0[xX][0-9a-fA-F]+", TK_HEX},
  {"[0-9]+", TK_DEC},
  {"\\$(\\$0|ra|sp|gp|tp|t[0-6]|s[0-9]|s1[0-1]|a[0-7]|x[0-9]{1,2}|pc|PC)", TK_REG},
  {"\\+", '+'},
  {"\\-", '-'},
  {"\\*", '*'},
  {"\\/", '/'},
  {"\\%", '%'},
  {"\\(", '('},
  {"\\)", ')'},
  {"==", TK_EQ},
  {"!=", TK_NEQ},
  {"&&", TK_AND},
  {"\\|\\|", TK_OR},
  {"!", TK_NOT},
  {"<=", TK_LE},
  {">=", TK_GE},
  {"<<", TK_SHL},
  {">>", TK_SHR},
  {"<", '<'},
  {">", '>'},
  {"&", '&'},
  {"\\|", '|'},
  {"\\^", '^'},
  {"~", '~'},
};

#define NR_REGEX (sizeof(rules) / sizeof(rules[0]))

typedef struct token {
  int type;
  char str[TOKEN_STR_SIZE];
} Token;

static regex_t re[NR_REGEX] = {};
static Token tokens[MAX_TOKENS] = {};
static int nr_token = 0;

void init_regex() {
  char error_msg[128];
  for (int i = 0; i < (int)NR_REGEX; i++) {
    int ret = regcomp(&re[i], rules[i].regex, REG_EXTENDED);
    if (ret != 0) {
      regerror(ret, &re[i], error_msg, sizeof(error_msg));
      fprintf(stderr, "regex compilation failed: %s\n%s\n", error_msg, rules[i].regex);
      abort();
    }
  }
}

static bool make_token(char *e) {
  int position = 0;
  regmatch_t pmatch;

  nr_token = 0;

  while (e[position] != '\0') {
    int i;
    for (i = 0; i < (int)NR_REGEX; i++) {
      if (regexec(&re[i], e + position, 1, &pmatch, 0) == 0 && pmatch.rm_so == 0) {
        char *substr_start = e + position;
        int substr_len = pmatch.rm_eo;
        position += substr_len;

        if (rules[i].token_type != TK_NOTYPE) {
          assert(nr_token < MAX_TOKENS);
          assert(substr_len < TOKEN_STR_SIZE);

          tokens[nr_token].type = rules[i].token_type;
          strncpy(tokens[nr_token].str, substr_start, substr_len);
          tokens[nr_token].str[substr_len] = '\0';
          nr_token++;
        }
        break;
      }
    }

    if (i == (int)NR_REGEX) {
      printf("no match at position %d\n%s\n%*.s^\n", position, e, position, "");
      return false;
    }
  }

  return true;
}

static bool check_parentheses(int p, int q) {
  if (tokens[p].type != '(' || tokens[q].type != ')') {
    return false;
  }

  int balance = 0;
  for (int i = p; i <= q; i++) {
    if (tokens[i].type == '(') balance++;
    else if (tokens[i].type == ')') {
      balance--;
      if (balance == 0 && i < q) return false;
    }
    if (balance < 0) return false;
  }
  return balance == 0;
}

static uint32_t eval(int p, int q, bool *success) {
  if (p > q) {
    *success = false;
    return 0;
  } else if (p == q) {
    switch (tokens[p].type) {
      case TK_HEX: return strtoul(tokens[p].str, NULL, 16);
      case TK_DEC: return strtoul(tokens[p].str, NULL, 10);
      case TK_REG: return npc_reg_str2val(tokens[p].str, success);
      default:
        *success = false;
        return 0;
    }
  } else if (check_parentheses(p, q)) {
    return eval(p + 1, q - 1, success);
  } else {
    int op = -1;
    int balance = 0;
    int min_prec = 100;

    for (int i = p; i <= q; i++) {
      if (tokens[i].type == '(') balance++;
      else if (tokens[i].type == ')') balance--;
      else if (balance == 0) {
        int prec = -1;
        switch (tokens[i].type) {
          case TK_OR: prec = 0; break;
          case TK_AND: prec = 1; break;
          case '|': prec = 2; break;
          case '^': prec = 3; break;
          case '&': prec = 4; break;
          case TK_EQ: case TK_NEQ: prec = 5; break;
          case '<': case '>': case TK_LE: case TK_GE: prec = 6; break;
          case TK_SHL: case TK_SHR: prec = 7; break;
          case '+': case '-': prec = 8; break;
          case '*': case '/': case '%': prec = 9; break;
          default: break;
        }
        if (prec >= 0 && prec <= min_prec) {
          min_prec = prec;
          op = i;
        }
      }
    }

    if (op == -1) {
      uint32_t val = eval(p + 1, q, success);
      if (!*success) return 0;

      switch (tokens[p].type) {
        case TK_NEG: return 0u - val;
        case TK_DEREF: {
          uint32_t data = 0;
          if (platform_read_word(val, &data)) return data;
          *success = false;
          return 0;
        }
        case TK_NOT: return !val;
        case '~': return ~val;
        default:
          *success = false;
          return 0;
      }
    }

    uint32_t val1 = eval(p, op - 1, success);
    if (!*success) return 0;

    if (tokens[op].type == TK_OR && val1) return 1;
    if (tokens[op].type == TK_AND && !val1) return 0;

    uint32_t val2 = eval(op + 1, q, success);
    if (!*success) return 0;

    switch (tokens[op].type) {
      case '+': return val1 + val2;
      case '-': return val1 - val2;
      case '*': return val1 * val2;
      case '/':
        if (val2 == 0) {
          *success = false;
          return 0;
        }
        return val1 / val2;
      case '%':
        if (val2 == 0) {
          *success = false;
          return 0;
        }
        return val1 % val2;
      case TK_EQ: return val1 == val2;
      case TK_NEQ: return val1 != val2;
      case TK_AND: return val1 && val2;
      case TK_OR: return val1 || val2;
      case TK_LE: return val1 <= val2;
      case TK_GE: return val1 >= val2;
      case TK_SHL: return val1 << val2;
      case TK_SHR: return val1 >> val2;
      case '<': return val1 < val2;
      case '>': return val1 > val2;
      case '&': return val1 & val2;
      case '|': return val1 | val2;
      case '^': return val1 ^ val2;
      default: assert(0);
    }
  }
}

uint32_t expr(char *e, bool *success) {
  if (!make_token(e)) {
    *success = false;
    return 0;
  }

  for (int i = 0; i < nr_token; i++) {
    if (tokens[i].type == '-' || tokens[i].type == '*') {
      bool unary = i == 0;
      if (!unary) {
        int prev_type = tokens[i - 1].type;
        unary = prev_type != TK_DEC && prev_type != TK_HEX && prev_type != TK_REG && prev_type != ')';
      }
      if (unary) {
        tokens[i].type = tokens[i].type == '-' ? TK_NEG : TK_DEREF;
      }
    }
  }

  *success = true;
  return eval(0, nr_token - 1, success);
}
