/***************************************************************************************
* Copyright (c) 2014-2024 Zihao Yu, Nanjing University
*
* NEMU is licensed under Mulan PSL v2.
* You can use this software according to the terms and conditions of the Mulan PSL v2.
* You may obtain a copy of Mulan PSL v2 at:
*          http://license.coscl.org.cn/MulanPSL2
*
* THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
* EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
* MERCHANTABILITY OR FIT FOR A PARTICULAR PURPOSE.
*
* See the Mulan PSL v2 for more details.
***************************************************************************************/

#include <isa.h>

/* We use the POSIX regex functions to process regular expressions.
 * Type 'man regex' for more information about POSIX regex functions.
 */
#include <regex.h>

word_t vaddr_read(word_t addr, int len);

enum {
  TK_NOTYPE = 256, TK_HEX, TK_DEC, TK_EQ, TK_NEG, TK_NEQ, TK_AND, TK_OR, TK_NOT, TK_DEREF, TK_REG, TK_LE, TK_GE, TK_SHL, TK_SHR,
};

static struct rule {
  const char *regex;
  int token_type;
} rules[] = {

  /* TODO: Add more rules.
   * Pay attention to the precedence level of different rules.
   */

  {" +", TK_NOTYPE},              // spaces
  {"0[xX][0-9a-fA-F]+", TK_HEX},  // hexadecimal num
  {"[0-9]+", TK_DEC},             // decimal num
  {"\\$(\\$0|ra|sp|gp|tp|t[0-6]|s[0-9]|s1[0-1]|a[0-7]|x[0-9]{1,2}|pc|PC)", TK_REG}, // register
  {"\\+", '+'},                   // plus
  {"\\-", '-'},                   // minus
  {"\\*", '*'},                   // multiply
  {"\\/", '/'},                   // divide
  {"\\%", '%'},                   // mod
  {"\\(", '('},                   // left parenthesis
  {"\\)", ')'},                   // right parenthesis
  {"==", TK_EQ},                  // equal
  {"!=", TK_NEQ},                 // not equal
  {"&&", TK_AND},                 // logical and
  {"\\|\\|", TK_OR},              // logical or
  {"!", TK_NOT},                  // logical not
  {"<=", TK_LE},                  // less than or equal
  {">=", TK_GE},                  // greater than or equal
  {"<<", TK_SHL},                 // shift left
  {">>", TK_SHR},                 // shift right
  {"<", '<'},                     // less than
  {">", '>'},                     // greater than
  {"&", '&'},                     // bitwise and
  {"\\|", '|'},                   // bitwise or
  {"\\^", '^'},                   // bitwise xor
  {"~", '~'},                     // bitwise not
};

#define NR_REGEX ARRLEN(rules)

static regex_t re[NR_REGEX] = {};

/* Rules are used for many times.
 * Therefore we compile them only once before any usage.
 */
void init_regex() {
  int i;
  char error_msg[128];
  int ret;

  for (i = 0; i < NR_REGEX; i ++) {
    ret = regcomp(&re[i], rules[i].regex, REG_EXTENDED);
    if (ret != 0) {
      regerror(ret, &re[i], error_msg, 128);
      panic("regex compilation failed: %s\n%s", error_msg, rules[i].regex);
    }
  }
}

typedef struct token {
  int type;
  char str[32];
} Token;

static Token tokens[65536] __attribute__((used)) = {};
static int nr_token __attribute__((used))  = 0;

static bool make_token(char *e) {
  int position = 0;
  int i;
  regmatch_t pmatch;

  nr_token = 0;

  while (e[position] != '\0') {
    /* Try all rules one by one. */
    for (i = 0; i < NR_REGEX; i ++) {
      if (regexec(&re[i], e + position, 1, &pmatch, 0) == 0 && pmatch.rm_so == 0) {
        char *substr_start = e + position;
        int substr_len = pmatch.rm_eo;

        #ifndef DEBUG
        Log("match rules[%d] = \"%s\" at position %d with len %d: %.*s",
            i, rules[i].regex, position, substr_len, substr_len, substr_start);
        #endif

        position += substr_len;

        /* TODO: Now a new token is recognized with rules[i]. Add codes
         * to record the token in the array `tokens'. For certain types
         * of tokens, some extra actions should be performed.
         */

        switch (rules[i].token_type) {
          case TK_NOTYPE:
            break;
          default:
            tokens[nr_token].type = rules[i].token_type;
            if (substr_len < 32) {
              strncpy(tokens[nr_token].str, substr_start, substr_len);
              tokens[nr_token].str[substr_len] = '\0';
            } else {
              strncpy(tokens[nr_token].str, substr_start, 31);
              tokens[nr_token].str[31] = '\0';
              Log("Token too long, truncated: %.*s", 31, substr_start);
            }
            nr_token ++;
            if (nr_token >= 65536) {
              Log("Too many tokens");
              return false;
            }
            break;
        }

        break;
      }
    }

    if (i == NR_REGEX) {
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
    if (tokens[i].type == '(') {
      balance++;
    } else if (tokens[i].type == ')') {
      balance--;
      if (balance == 0 && i < q) {
        return false;
      }
    }
    if (balance < 0) return false;
  }
  return balance == 0;
}

static word_t eval(int p, int q, bool *success) {
  if (p > q) {
    /* Bad expression */
    *success = false;
    return 0;
  }
  else if (p == q) {
    /* Single token.
     * For now this token should be a number.
     * Return the value of the number.
     */
    if (tokens[p].type == TK_HEX) {
      return strtol(tokens[p].str, NULL, 16);
    }
    else if (tokens[p].type == TK_DEC) {
      return strtol(tokens[p].str, NULL, 10);
    }
    else if (tokens[p].type == TK_REG) {
      return isa_reg_str2val(tokens[p].str, success);
    }
    else {
      *success = false;
      return 0;
    }
  }
  else if (check_parentheses(p, q) == true) {
    /* The expression is surrounded by a matched pair of parentheses.
     * If that is the case, just throw away the parentheses.
     */
    return eval(p + 1, q - 1, success);
  }
  else {
    int op = -1;
    int balance = 0;
    // Priority (lowest to highest):
    // 0: ||
    // 1: &&
    // 2: |
    // 3: ^
    // 4: &
    // 5: == !=
    // 6: < > <= >=
    // 7: << >>
    // 8: + -
    // 9: * / %
    int min_prec = 100;

    for (int i = p; i <= q; i++) {
      if (tokens[i].type == '(') balance++;
      else if (tokens[i].type == ')') balance--;
      else if (balance == 0) {
        int curr_prec = 100;
        switch (tokens[i].type) {
          case TK_OR: curr_prec = 0; break;
          case TK_AND: curr_prec = 1; break;
          case '|': curr_prec = 2; break;
          case '^': curr_prec = 3; break;
          case '&': curr_prec = 4; break;
          case TK_EQ: case TK_NEQ: curr_prec = 5; break;
          case '<': case '>': case TK_LE: case TK_GE: curr_prec = 6; break;
          case TK_SHL: case TK_SHR: curr_prec = 7; break;
          case '+': case '-': curr_prec = 8; break;
          case '*': case '/': case '%': curr_prec = 9; break;
          default: continue;
        }
        if (curr_prec <= min_prec) {
          min_prec = curr_prec;
          op = i;
        }
      }
    }

    if (op == -1) {
      if (tokens[p].type == TK_NEG) {
        word_t val = eval(p + 1, q, success);
        if (!*success) return 0;
        return (word_t)(0u - val);
      }
      if (tokens[p].type == TK_DEREF) {
        word_t addr = eval(p + 1, q, success);
        if (!*success) return 0;
        return vaddr_read(addr, 4);
      }
      if (tokens[p].type == TK_NOT) {
        word_t val = eval(p + 1, q, success);
        if (!*success) return 0;
        return !val;
      }
      if (tokens[p].type == '~') {
        word_t val = eval(p + 1, q, success);
        if (!*success) return 0;
        return ~val;
      }
      *success = false;
      return 0;
    }

    word_t val1 = eval(p, op - 1, success);
    if (!*success) return 0;
    word_t val2 = eval(op + 1, q, success);
    if (!*success) return 0;

    switch (tokens[op].type) {
      case '+': return val1 + val2;
      case '-': return val1 - val2;
      case '*': return val1 * val2;
      case '/': 
        if (val2 == 0) {
          Log("Division by zero");
          *success = false;
          return 0;
        }
        return val1 / val2;
      case '%': 
        if (val2 == 0) {
          Log("Division by zero");
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

word_t expr(char *e, bool *success) {
  if (!make_token(e)) {
    *success = false;
    return 0;
  }

  for (int i = 0; i < nr_token; i++) {
    // Unary Minus
    if (tokens[i].type == '-') {
      if (i == 0) {
        tokens[i].type = TK_NEG;
      } else {
        int prev_type = tokens[i - 1].type;
        if (prev_type != TK_DEC && prev_type != TK_HEX && prev_type != TK_REG && prev_type != ')') {
          tokens[i].type = TK_NEG;
        }
      }
    }
    
    // Pointer Dereference
    if (tokens[i].type == '*') {
      if (i == 0) {
        tokens[i].type = TK_DEREF;
      } else {
        int prev_type = tokens[i - 1].type;
        if (prev_type != TK_DEC && prev_type != TK_HEX && prev_type != TK_REG && prev_type != ')') {
          tokens[i].type = TK_DEREF;
        }
      }
    }
  }

  *success = true;
  return eval(0, nr_token - 1, success);
}
