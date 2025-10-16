# Base game implementation (single player, 1 match, 1 candle, 1 shadow monster)
# Targe# Target simulator: CPUlator (RISC‑V RV32). Also compatible with RARS syscalls.OW TO RUN (RARS):
# 1) Open this file in RARS.
# 2) Assemble.
# 3) Run. Use W/A/S/D to move, R to restart, Q to quit.
# 4) Symbols:
# # = wall border
# . = floor
# P = player
# M = match (pick up)
# C = candle (light it when you have the match)
# X = shadow monster (moves 1 step toward you after you move)
# 5) Messages print for invalid moves, candle lit, fear increased, and game over.
# 6) Grid size is configurable via `gridsize` (width,height), not assumed 8x8.
#
# RANDOMNESS ALGORITHM CITATION:
# We use **xorshift32** — George Marsaglia (2003), “Xorshift RNGs”.
# Reference: Marsaglia, G. 2003. Xorshift RNGs. Journal of Statistical Software 8(14).
# This is a small, fast RNG with a 32-bit state. Code below in `rand32`.
# Bounded randoms use `remu` (simple modulus) for 0..MAX-1.
#
# ENHANCEMENTS:
# [complete] Enhancement A (Memory): Provide unlimited undos to the player.
# - Allows the player to undo an unlimited number of moves in a row
# - This would also undo a shadow monster move, put a match down if they picked one up, and unlight a candle if it got lit up.
# [complete] Enhancement B (Memory): A multi-player (competitive) mode
# - program should prompt for the number of players prior to starting the game
# - Each player should be given a chance to play the same map each round
# - The program should track the fear gauge each player had at the end of their round and should display the cumulative standings (ordered by fear gauge) as a single leaderboard after the entire round is complete
# -----------------------------------------------------------------------------

#------------------------------------------------------------------------------
# Macros:
#------------------------------------------------------------------------------
.macro PRINT_CHAR r
    mv   a0, \r
    li   a7, 11          # print_char
    ecall
.endm

# print a zero-terminated string at label \addr
.macro PRINT_STR addr
    la   a0, \addr
    li   a7, 4           # print_string
    ecall
.endm

# newline (just '\n'; if you want CRLF, print 13 then 10)
.macro PRINT_NL
    li   a0, 10
    li   a7, 11
    ecall
.endm

# print an integer in \r (decimal)
.macro PRINT_INT r
    mv   a0, \r
    li   a7, 1           # print_int
    ecall
.endm

# blocking read of one character -> \dest
.macro READ_CHAR dest
    li   a7, 12          # read_char
    ecall
    mv   \dest, a0
.endm
# Game state 
.data
gridsize: .byte 8,8

# entity positions are interior coordinates
player_x: .byte 0
player_y: .byte 0
match_x: .byte 0
match_y: .byte 0
candle_x: .byte 0
candle_y: .byte 0
monster_x: .byte 0
monster_y: .byte 0

fearFactor: .byte 0
has_match: .byte 0
candle_lit: .byte 0

.align 2

# RNG state (xorshift 32)
rand_state: .word 2463534242 # default seed to use xorshift 32

# UI strings
welcome_msg: .asciz "----------------------------------------Welcome to the Haunted house!\nYou are in a dark room. You can move using W (up), A (left), S (down), D (right).\nPress R to restart (same map), N for a new map, Q to quit.\n----------Objective:\n----------------------------------------Light the candle (C) using the match (M)\n----------------------------------------The Player (P) is you\nAvoid the shadow monster (X)!\nYour fear factor increases by 10 when a shadow monster gets adjacent.\nOnce your fear factor = 100, the Game is Over\nGood luck!\n----------------------------------------\n"
status_prefix: .asciz "Status: Fear = "
status_mid1: .asciz ", Match = "
status_mid2: .asciz ", Candle = "
status_lit: .asciz "lit"
status_unlit: .asciz "unlit"
msg_invalid: .asciz "Cannot move there (Wall)\n"
msg_picked: .asciz "You picked up the match.\n"
msg_lit: .asciz "Candle lit! You have gotten rid of the shadows. Congradulations, You Win!\n"
msg_fear: .asciz "A Shadow Monster was next to you - Your fear increases by 10\n"
msg_over: .asciz "Your fear reached 100. Game over\n"
msg_restart: .asciz "Restarting game ...\n\n"
msg_final_board: .asciz "Final board state:\n"
msg_user_pressed_quit: .asciz "User has requested to quit (Q) the game. Thanks for playing!\n"
msg_newmap: .asciz "Starting a new map ...\n\n"
msg_restart_same: .asciz "Restarting same map ...\n\n"

# --- Undo ring buffer ---
.equ STATE_SZ, 12          # 12 bytes listed above
.equ HIST_CAP, 128         # plenty for an 8x8

.align 2
hist_top:      .word 0
history:       .space STATE_SZ*HIST_CAP
msg_undo:      .asciz "Undid last move.\n"
msg_noundo:    .asciz "You've reached the start of the current game, nothing to undo.\n"

# potential multiplayer stuff
seed_state: .space 11      # same size/order as STATE_SZ snapshot
.align 2
level_seed: .word 0

# ----- multi-player config & state -----
.equ MAX_PLAYERS, 8           # you can raise this later

players_count: .byte 1        # set at runtime
scores:        .space MAX_PLAYERS   # fear at end of each player's round
order_idx:     .space MAX_PLAYERS   # index list for sorting/printing

# round-finished flag (win OR fear-100); lets game_loop return instead of exiting
round_over:    .byte 0

# --- messages ---
prompt_players_str:   .asciz "How many players? (1-8): "
msg_player_turn1: .asciz "\n--- Player "
msg_player_turn2: .asciz " turn ---\n"
msg_leaderboard:  .asciz "==Leaderboard (by fear, low->high)==\n"
msg_rank_sep:     .asciz ": Player "
msg_fear_sep:     .asciz "  Fear = "
msg_next_turn: .asciz "Press any key to go to the next player's turn\n"
msg_all_turns_done: .asciz "\nPress any key to end the game...\n"
msg_end_turn_hint: .asciz "Press any key to finish your turn (or R=restart same map, N=new map, U=undo, Q=quit)...\n"
#--end of multiplayer stuff--------

#----debug
.dbgP: .asciz "DBG P: "
.dbgM: .asciz "DBG M: "
.dbgC: .asciz "DBG C: "
.dbgX: .asciz "DBG X: "
#-------------------
# 1 byte scratch buffer for printing visual characters
ch_buf: .byte 0


.text
.global main
_start:
	j main
main:
    # TODO: Generate locations for the character, match, stick, and shadow monster.
	# Static locations in memory have been provided for the (x, y) coordinates 
    # of each of these elements.
    
    # There is a notrand function that you can use to start with. It's 
    # really not very good; you will replace it with your own rand function
    # later. Regardless of the source of your "random" locations, make 
    # sure that none of the items are on top of each other.
   
    # TODO: Now, print the gameboard. Select symbols to represent the floors/walls,
    # character, match, stick, and shadow monster. Write a function that uses
	# the location of the various elements (in memory) to construct a gameboard
	# and that prints that board one character at a time.
    # HINT: You may wish to construct the string that represents the board
    # and then print that string with a single syscall. If you do this, 
    # consider whether you want to place this string in static memory or 
    # on the stack. 

    # TODO: Enter a loop and wait for user input. Whenever user input is
    # received, update the gameboard state with the new location of the 
    # player and shadow monster. Print a message if the input received is
	# invalid (e.g. walking into a wall), or if game events occur
	# (e.g. picked up match, fear factor increased).
	# Otherwise, just print the updated game state. 
    
    # You will also need to restart the game if the user requests it
	# It may be useful for this loop to exist in a function,
    # to make it cleaner to exit the game loop.

    # TODO: That's the base game! Now, pick a pair of enhancements and
    # consider how to implement them.

    
    # beginning
    addi sp, sp, -16 # 4 spaces on stack
    sw ra, 12(sp)
    jal ra, seed_from_time
	jal ra, save_rng_seed
    PRINT_STR welcome_msg
    jal ra, prompt_players
	jal ra, run_round #### important
    jal ra, print_leaderboard
	
	PRINT_STR msg_all_turns_done
	READ_CHAR t0
    # on return we exit
    lw ra, 12(sp)
    addi sp, sp, 16

    li a7, 10
    ecall
# ------------------------------------------------------------------------------------------
# init_game - (re) initialize the state, make sure to spawn the entities without overlapping
#-------------------------------------------------------------------------------------------
.globl init_game

init_game:
    addi sp, sp, -24
    sw ra, 20(sp)
	sw s0, 16(sp)
	sw s1, 12(sp) # candidate x
	sw s2, 8(sp) # candidate y

    # Reset the flags and clear
    li t0, 0
	la s0, fearFactor
    sb t0, 0(s0)
    la s0, has_match
	sb t0, 0(s0)
	la s0, candle_lit
    sb t0, 0(s0)
	
	# reset round finished flag
	la s0, round_over
	sb zero, 0(s0)
	
	#new-> clear the undo stack head\
	la t1, hist_top
	sw zero, 0(t1)

    # width (t4), and height (t5)
	la s0, gridsize
    lbu t4, 0(s0)
	la s0, gridsize+1
    lbu t5, 0(s0)

    # place the player
1:  mv a0, t4
    jal ra, rand_bounded # a0 <-- 0,...,w-1
	la s0, player_x
    sb a0, 0(s0)
    mv a0, t5
    jal ra, rand_bounded
	la s0, player_y
    sb a0, 0(s0)

    # place the match (cannot be on the player)
2:  mv a0, t4
    jal ra, rand_bounded
    mv s1, a0 # x
    mv a0, t5
    jal ra, rand_bounded
    mv s2, a0 # y
    # compare with player position
	la s0, player_x
    lbu t2, 0(s0)
	la s0, player_y
    lbu t3, 0(s0)
    beq s1, t2, 2b
	beq s2, t3, 2b

	la s0, match_x
	sb s1, 0(s0)
	la s0, match_y
    sb s2, 0(s0)

    # place the candle (cannot be on player or match)
4:  mv a0, t4
    jal ra, rand_bounded
    mv s1, a0	# candidate x
    mv a0, t5
    jal ra, rand_bounded
    mv s2, a0
	#vs player
	la s0, player_x
    lbu t2, 0(s0)
	la s0, player_y
    lbu t3, 0(s0)
    beq s1, t2, 4b
    beq s2, t3, 4b
	#vs match
	la s0, match_x
    lbu t2, 0(s0)
	la s0, match_y
    lbu t3, 0(s0)
    beq s1, t2, 4b
    beq s2, t3, 4b
	
	la s0, candle_x
    sb s1, 0(s0)
	la s0, candle_y
    sb s2, 0(s0)

    # place the shadow monster (cannot be on player/match/candle)
5:
    mv a0, t4
    jal ra, rand_bounded
    mv s1, a0 	# candidate mx
    mv a0, t5
    jal ra, rand_bounded
    mv s2, a0	# candidate my
    #check vs player
	la s0, player_x
    lbu t2, 0(s0)
	la s0, player_y
    lbu t3, 0(s0)
    beq s1, t2, 5b
    beq s2, t3, 5b
    # check vs match
	la s0, match_x
    lbu t2, 0(s0)
	la s0, match_y
    lbu t3, 0(s0)
    beq s1, t2, 5b
    beq s2, t3, 5b
    #check vs candle
	la s0, candle_x
    lbu t2, 0(s0)
	la s0, candle_y
    lbu t3, 0(s0)
    beq s1, t2, 5b
    beq s2, t3, 5b
	
	la s0, monster_x
    sb s1, 0(s0)
	la s0, monster_y
    sb s2, 0(s0)
	
	lw s2, 8(sp)
	lw s1, 12(sp)
	lw s0, 16(sp)
    lw ra, 20(sp)
    addi sp, sp, 24
    ret

#---------------------------------------------------------------
# game_loop: process inputs, update the world, render the world
#---------------------------------------------------------------
.globl game_loop

game_loop:
    addi sp, sp, -48 # allocate 8 spaces in stack
    sw ra, 44(sp)
	sw s1, 40(sp)
	sw s2, 36(sp)

.loop:
    # read a keystroke
    READ_CHAR t0
	#move to fresh line after printing anything else (before printing new board and prompt on terminal)
	li a0, 13 # '\r'
	li a7, 11 # print char
	ecall
	li a0, 10 # '\n'
	li a7, 11
	ecall

    # normalize into upper case if a...z
    li t1, 'a'
    li t2, 'z'
    blt t0, t1, 1f
    bgt t0, t2, 1f
    addi t0, t0, -32 # to uppercase

1: # handle Q/R/U/N
    li t1, 'Q'
    beq t0, t1, .quit
	
    li t1, 'R'
    beq t0, t1, .do_restart_same # restart same map
	
	li t1, 'N'
	beq t0, t1, .do_new_map # restart random new map
	
	li t1, 'U'
	beq t0, t1, .do_undo
	
	j .after_ctrl
	
.do_restart_same:
    PRINT_STR msg_restart_same
	jal ra, restore_rng_seed
    jal ra, init_game
    jal ra, draw_board_and_status
    j .loop

.do_new_map:
	PRINT_STR msg_newmap
	jal ra, seed_from_time
	jal ra, save_rng_seed
	jal ra, init_game
	jal ra, draw_board_and_status
	j .loop
	
.do_undo:
	jal ra, snapshot_pop_restore
	beqz t0, .noundo
	
	PRINT_STR msg_undo
	jal ra, draw_board_and_status
	j .loop

.noundo:
	PRINT_STR msg_noundo
	jal ra, draw_board_and_status
	j .loop

.after_ctrl:
	# if round is already over (dead) or candle lit (win),
	# return to run_round unless the key was q,r,n,u
	la t4, round_over
	lbu t5, 0(t4)
	bnez t5, .finish_round
	
	la t4, candle_lit
	lbu t5, 0(t4)
	bnez t5, .finish_round
	# fall through to movement

# now we handle movement
2: # calculate the needed (dx, dy) into s1, s2
    li s1, 0 # dx
    li s2, 0 # dy
    li t1, 'W'
    bne t0, t1, 3f
    li s2, -1 # up
    j 5f

3:  li t1, 'S'
    bne t0, t1, 4f
    li s2, 1 # down
    j 5f

4:  li t1, 'A'
    bne t0, t1, 6f
    li s1, -1 # left
    j 5f

6:  li t1, 'D'
    bne t0, t1, .noop
    li s1, 1 # right

5:  # attempt the player move
	jal ra, snapshot_push # snapshot state before attempting the players move
	
    jal ra, try_move_player
    beqz t3, .invalid
	
	# 'if the candle is already lit, we won
	la t4, candle_lit
	lbu t1, 0(t4)
	bnez t1, .finish_after_win
	
	# otherwise continue, monster moves and continue
	jal ra, monster_step_towards_player
	jal ra, check_shadow_monster_adjacency
	
	# redraw and keep playing
	jal  ra, draw_board_and_status
    j .loop

.finish_after_win:
	PRINT_STR msg_final_board
    # after updates, redraw the board
    jal ra, draw_board_and_status
	PRINT_STR msg_end_turn_hint
    j .loop
	
.finish_round:
	lw s2, 36(sp)
	lw s1, 40(sp)
    lw ra, 44(sp)
    addi sp, sp, 48
    ret
	
.invalid:
	# we pushed before trying, move failed so get rid of that snapshot
	jal ra, snapshot_discard
	
    PRINT_STR msg_invalid
    jal ra, draw_board_and_status
    j .loop

.noop:
    # ignore other keys, keep board still visible
    jal ra, draw_board_and_status
    j .loop

.quit:
	PRINT_STR msg_user_pressed_quit
	lw s2, 36(sp)
	lw s1, 40(sp)
    lw ra, 44(sp)
    addi sp, sp, 48
    ret

#-------------------------------------------------------------------
# try_move_player -> dx = s1, dy = s2, attemps to move within bounds
#   returns t3 = 1 if moved, otherwise
#   also handles pickup and candle lighting (with printed messages)
# ------------------------------------------------------------------
.globl try_move_player

try_move_player:
    addi sp, sp, -32 # allocate 8 spaces again
    sw ra, 28(sp)
	sw s0, 24(sp)

    # load dimensions (again)
	la s0, gridsize
    lbu t0, 0(s0) # width
	la s0, gridsize+1
    lbu t1, 0(s0) # height

    # current position
	la s0, player_x
    lbu t4, 0(s0)
	la s0, player_y
    lbu t5, 0(s0)

    # new position = old + delta(check that 0...w-1, 0...h-1)
    add t6, t4, s1 # newx
    add a5, t5, s2 # newy

    # check that 0<=newx<=w
    bltz t6, .blocked
    bltz a5, .blocked
    bge t6, t0, .blocked
    bge a5, t1, .blocked

    # commit the move
    mv t3, zero
	la s0, player_x
    sb t6, 0(s0)
	la s0, player_y
    sb a5, 0(s0)
    li t3, 1 # moved

    # pickup the match if present and not already holding it
	la s0, has_match
    lbu t2, 0(s0)
    bnez t2, 1f
	
	la s0, match_x
    lbu t0, 0(s0)
	la s0, match_y
    lbu t1, 0(s0)
    bne t6, t0, 1f
    bne a5, t1, 1f

    li t2, 1
	la s0, has_match
    sb t2, 0(s0)
    PRINT_STR msg_picked

    # hide match by moving off the grid
    li t2, 255
	la s0, match_x
    sb t2, 0(s0)
	la s0, match_y
    sb t2, 0(s0)

1:  # light the candle if on it and have a match, and not already lit
    la s0, candle_lit
	lbu t0, 0(s0)
    bnez t0, 2f
	la s0, has_match
    lbu t2, 0(s0)
    beqz t2, 2f
	la s0, candle_x
    lbu t0, 0(s0)
	la s0, candle_y
    lbu t1, 0(s0)
    bne t6, t0, 2f
    bne a5, t1, 2f
    # light the candle!!!
    li t2, 1
	la s0, candle_lit
    sb t2, 0(s0)
    PRINT_STR msg_lit

2: j .ret

.blocked:
    mv t3, zero

.ret:
 	lw s0, 24(sp)
    lw ra, 28(sp)
    addi sp, sp, 32
    ret

#------------------------------------------------------------------------------
# monster_step_towards_player -> move monster 1 step towards player
# note: step along x if x differs, else step along y
#------------------------------------------------------------------------------
.globl monster_step_towards_player

monster_step_towards_player:
    addi sp, sp, -16 # allocate 4 spaces in stack for 4 words
    sw ra, 12(sp)
	sw s0, 8(sp)
	
	la s0, player_x
    lbu t0, 0(s0)
	la s0, player_y
    lbu t1, 0(s0)
	la s0, monster_x
    lbu t2, 0(s0)
	la s0, monster_y
    lbu t3, 0(s0)

    #dx = sign(px - mx)
    sub t4, t0, t2
    beqz t4, 1f
    # "if" t4>0 then mx++, else mx--
    bgtz t4, 2f
    addi t2, t2, -1
    j 3f

2:  addi t2, t2, 1 # mx++
    j 3f

1:  #dy = sign(py - my) only if the same x
    sub t5, t1, t3
    beqz t5, 3f
    bgtz t5, 4f
    addi t3, t3, -1
    j 3f

4:  addi t3, t3, 1

3:  # Restrict inside 0...w-1 / 0...h-1 just in case.
	la s0, gridsize
    lbu t6, 0(s0) # width
	la s0, gridsize+1
    lbu a5, 0(s0) #height
    #check if t2 in 0...w-1
    bltz t2, 5f
    bge t2, t6, 6f
    j 7f

5:  li t2, 0
    j 7f

6: addi t2, t6, -1

7: # check if t3 in 0...h-1
    bltz t3, 8f
    bge t3, a5, 9f
    j 10f

8:  li t3, 0
    j 10f
 
9:  addi t3, a5, -1

10: la s0, monster_x
	sb t2, 0(s0)
	la s0, monster_y
    sb t3, 0(s0)
	
	lw s0, 8(sp)
    lw ra, 12(sp)
    addi sp, sp, 16
    ret

#--------------------------------------------------------------------------------
# check_shadow_monster_adjacency -> if |dx|+|dy| <= 1, fear +=10, respawn monster
#   and print fear message if fear >=100, the game is over and end the program
#--------------------------------------------------------------------------------
.globl check_shadow_monster_adjacency

check_shadow_monster_adjacency:
    addi sp, sp, -32 # allocate 8 words to be stored in stack
    sw ra, 28(sp)
	sw s0, 24(sp)
	
	la s0, player_x
    lbu t0, 0(s0)
	la s0, player_y
    lbu t1, 0(s0)
	la s0, monster_x
    lbu t2, 0(s0)
	la s0, monster_y
    lbu t3, 0(s0)

    sub t4, t0, t2 # dx
    sub t5, t1, t3 # dy
    # abs(dx)
    bltz t4, 1f
    mv t6, t4
    j 2f

1:  sub t6, zero, t4

2:  # abs(dy)
    bltz t5, 3f
    mv a5, t5
    j 4f

3:  sub a5, zero, t5

4:  add t6, t6, a5 # t6 = |dx|+|dy|
    li t4, 1
    blt t4, t6, .nohit # if t6 > 1 -> nohit (else hit on 0 or 1)

    # fear+=10
	la s0, fearFactor
    lbu t0, 0(s0)
    addi t0, t0, 10
    sb t0, 0(s0)
    PRINT_STR msg_fear

    # is game over?
    li t1, 100
    blt t0, t1, 5f
    PRINT_STR msg_over
    # mark_round_complete; game loop will return to the round controller
	la s0, round_over
	li t2, 1
	sb t2, 0(s0)
	
	PRINT_STR msg_end_turn_hint
	
	j .nohit

5:  # respawn the monster to a new free cell
	la s0, gridsize
    lbu t4, 0(s0) #width
	la s0, gridsize+1
    lbu t5, 0(s0) #height

6:  mv a0, t4
    jal ra, rand_bounded
    mv t6, a0 # randomx
    mv a0, t5

    jal ra, rand_bounded
    mv a5, a0 #random y

    # dont allow overlapping with player/candle(if unlit)/match (if not picked up)

    #player
	la s0, player_x
    lbu t0, 0(s0)
	la s0, player_y
    lbu t1, 0(s0)
    beq t6, t0, 6b # reloop
    beq a5, t1, 6b

    # is candle present?
	la s0, candle_lit
    lbu t2, 0(s0)
    bnez t2, 7f
	
	la s0, candle_x
    lbu t0, 0(s0)
	la s0, candle_y
    lbu t1, 0(s0)
    beq t6, t0, 6b
    beq a5, t1, 6b

7:  # is match present?
	la s0, has_match
    lbu t2, 0(s0)
    bnez t2, 8f
	
	la s0, match_x
    lbu t0, 0(s0)
	la s0, match_y
    lbu t1, 0(s0)
    beq t6, t0, 6b
    beq a5, t1, 6b

8:  la s0, monster_x
	sb t6, 0(s0)
	la s0, monster_y
    sb a5, 0(s0)

.nohit:
	lw s0, 24(sp)
    lw ra, 28(sp)
    addi sp, sp, 32
    ret


#-------------------------------------------------------------------
# draw_board_and_status -> renders the bordered grid and status line
#-------------------------------------------------------------------
.globl draw_board_and_status

draw_board_and_status:
    addi sp, sp, -16 # allocate for 12 words on stack
    sw ra, 12(sp)
	sw s0, 8(sp)
	# dimensions
	la s0, gridsize
    lbu t0, 0(s0) #width
	la s0, gridsize+1
    lbu t1, 0(s0) #height

    #top border: (width+2) '#'
    li a4, '#'
    addi t3, t0, 2 # count

.top_loop:
    beqz t3, .top_done
    PRINT_CHAR a4
    addi t3, t3, -1
    j .top_loop

.top_done:
    PRINT_NL
    #for each interior row, 
    li t4, 0 # since y = 0...h-1

.row_loop:
    bge t4, t1, .rows_done
    # left border '#'
    PRINT_CHAR a4

    li t5, 0 # x = 0...w-1

.col_loop:
    bge t5, t0, .row_right

    # decide character for cell (x=t5, y=t4)
    # default '.'
    li t6, '.'
	 
	# unlit: show candle 'C' if at (x,y)
	la s0, candle_lit
	lbu a5, 0(s0)
	bnez a5, .skip_candle
	
	la s0, candle_x
    lbu t2, 0(s0)
	bne t5, t2, .skip_candle
	
	la s0, candle_y
    lbu t3, 0(s0)
    bne t4, t3, .skip_candle
	
    li t6, 'C'

.skip_candle: # show match 'M' if not picked up and at (x,y)
	la s0, has_match
	lbu a5, 0(s0)
	bnez a5, .skip_match
	
	la s0, match_x
    lbu t2, 0(s0)
	bne t5, t2, .skip_match
	
	la s0, match_y
    lbu t3, 0(s0)
    bne t4, t3, .skip_match
	
    li t6, 'M'

.skip_match:  #show monster 'X'
	la s0, monster_x
    lbu t2, 0(s0)
	bne t5, t2, .skip_monster
	
	la s0, monster_y
    lbu t3, 0(s0)
    bne t4, t3, .skip_monster
	
    li t6, 'X'

.skip_monster:  # show player 'P' (player overwrites another other symbol visually)
    la s0, player_x
	lbu t2, 0(s0)
	bne t5, t2, .emit

	la s0, player_y
    lbu t3, 0(s0)
    bne t4, t3, .emit
	
    li t6, 'P'

.emit:  
	PRINT_CHAR t6
    addi t5, t5, 1
    j .col_loop

.row_right:
    # right border with '#'
    PRINT_CHAR a4
    PRINT_NL

    addi t4, t4, 1
    j .row_loop

.rows_done:
    addi t3, t0, 2

.bottom_loop:
    beqz t3, .bottom_done
    PRINT_CHAR a4
    addi t3, t3, -1
    j .bottom_loop

.bottom_done:
    PRINT_NL

    #status line: Fear, Match, Candle
    PRINT_STR status_prefix # prints fear=
	la s0, fearFactor
    lbu t2, 0(s0)
    PRINT_INT t2

    PRINT_STR status_mid1 # prints match=
	la s0, has_match
	lbu t2, 0(s0)
    PRINT_INT t2 	# has_match (0/1)

    PRINT_STR status_mid2 # prints candle=
	la s0, candle_lit
	lbu t2, 0(s0)
	
	beqz t2, .show_unlit
	PRINT_STR status_lit

    j .status_end

.show_unlit:
    PRINT_STR status_unlit

.status_end:
    PRINT_NL
	
	lw s0, 8(sp)
    lw ra, 12(sp)
    addi sp, sp, 16

    ret


#--------------------------------------------------------------------------------
# rand32 - xorshift32 (Marsaglia 2003)
#   returns a0 = a new 32 bit random
# -------------------------------------------------------------------------------
.globl rand32

rand32:
	la t1, rand_state
    lw t0, 0(t1)
    slli t2, t0, 13
    xor t0, t0, t2
    srli t2, t0, 17
    xor t0, t0, t2
    slli t2, t0, 5
    xor t0, t0, t2
    sw t0, 0(t1)
    mv a0, t0
    ret

#---------------------------------------------------
# rand_bounded -> a0=max -> returns a0 in [0,MAX-1]
#---------------------------------------------------
.globl rand_bounded

rand_bounded:
    addi sp, sp, -16 # allocate space for 4 words
    sw ra, 12(sp)

    mv t3, a0
    beqz t3, .rb_zero # if MAX==0, return 0 (so we dont divide by 0)

	jal ra, rand32
    remu a0, a0, t3 # modulus
	j .rb_done
.rb_zero:
	mv a0, zero
.rb_done:
    lw ra, 12(sp)
    addi sp, sp, 16
    ret

#-----------------------------------------------------------
# seed_from_time - seeds the rand_state with time syscall 30
#-----------------------------------------------------------
.globl seed_from_time

seed_from_time:
    # mix a constant with SP and RA so it isn't all-zero
    li   t0, 0x9E3779B9       # golden ratio constant
    mv   t1, sp
    mv   t2, ra
    xor  t0, t0, t1
    xor  t0, t0, t2
	bnez t0, 1f
	li t0, 1
1: 
    la   t3, rand_state
    sw   t0, 0(t3)
    ret

#state history helpers:
# push current state to history (no wrap handling shown -> use modulo)
# a0..a2 clobbered, saves/loads with lb/sb
snapshot_push:
    addi sp, sp, -16
    sw   ra, 12(sp)

    la   t0, hist_top
    lw   t1, 0(t0)                 # t1 = top
    li   t2, STATE_SZ
    mul  t3, t1, t2                # offset = top*STATE_SZ
    la   t4, history
    add  t4, t4, t3

    # write bytes in a fixed order
    la a0, player_x; lbu a1, 0(a0); sb a1, 0(t4)
    la a0, player_y; lbu a1, 0(a0); sb a1, 1(t4)
    la a0, match_x ; lbu a1, 0(a0); sb a1, 2(t4)
    la a0, match_y ; lbu a1, 0(a0); sb a1, 3(t4)
    la a0, candle_x; lbu a1, 0(a0); sb a1, 4(t4)
    la a0, candle_y; lbu a1, 0(a0); sb a1, 5(t4)
    la a0, monster_x; lbu a1, 0(a0); sb a1, 6(t4)
    la a0, monster_y; lbu a1, 0(a0); sb a1, 7(t4)
    la a0, has_match; lbu a1, 0(a0); sb a1, 8(t4)
    la a0, candle_lit; lbu a1, 0(a0); sb a1, 9(t4)
    la a0, fearFactor; lbu a1, 0(a0); sb a1, 10(t4)
	la a0, round_over; lbu a1, 0(a0); sb a1, 11(t4)
	
    addi t1, t1, 1
    li   t2, HIST_CAP
    rem  t1, t1, t2                # wrap
    sw   t1, 0(t0)

    lw ra, 12(sp)
    addi sp, sp, 16
    ret

# undo_prepare_invalid: undo the push if move was invalid
snapshot_discard:
    addi sp, sp, -16
    sw   ra, 12(sp)
    la   t0, hist_top
    lw   t1, 0(t0)
    addi t1, t1, -1
    li   t2, HIST_CAP
    add  t1, t1, t2
    rem  t1, t1, t2
    sw   t1, 0(t0)
    lw   ra, 12(sp)
    addi sp, sp, 16
    ret

# pop & restore last state (returns t0=0 if none, 1 if restored)
snapshot_pop_restore:
    addi sp, sp, -16
    sw   ra, 12(sp)
    la   t0, hist_top
    lw   t1, 0(t0)
    beqz t1, .nope

    addi t1, t1, -1
    li   t2, HIST_CAP
    add  t1, t1, t2
    rem  t1, t1, t2
    sw   t1, 0(t0)

    li   t2, STATE_SZ
    mul  t3, t1, t2
    la   t4, history
    add  t4, t4, t3

    lb a1, 0(t4); la a0, player_x ; sb a1, 0(a0)
    lb a1, 1(t4); la a0, player_y ; sb a1, 0(a0)
    lb a1, 2(t4); la a0, match_x  ; sb a1, 0(a0)
    lb a1, 3(t4); la a0, match_y  ; sb a1, 0(a0)
    lb a1, 4(t4); la a0, candle_x ; sb a1, 0(a0)
    lb a1, 5(t4); la a0, candle_y ; sb a1, 0(a0)
    lb a1, 6(t4); la a0, monster_x; sb a1, 0(a0)
    lb a1, 7(t4); la a0, monster_y; sb a1, 0(a0)
    lb a1, 8(t4); la a0, has_match; sb a1, 0(a0)
    lb a1, 9(t4); la a0, candle_lit; sb a1, 0(a0)
    lb a1, 10(t4); la a0, fearFactor; sb a1, 0(a0)
	lb a1, 11(t4); la a0, round_over;  sb a1, 0(a0)

    li t0, 1
    j .done
.nope:
    li t0, 0
.done:
    lw ra, 12(sp)
    addi sp, sp, 16
    ret

# Save current state into seed_state (same 11-byte order as snapshots)
.globl save_seed_state
save_seed_state:
    la t4, seed_state
    la a0, player_x ; lbu a1,0(a0); sb a1, 0(t4)
    la a0, player_y ; lbu a1,0(a0); sb a1, 1(t4)
    la a0, match_x  ; lbu a1,0(a0); sb a1, 2(t4)
    la a0, match_y  ; lbu a1,0(a0); sb a1, 3(t4)
    la a0, candle_x ; lbu a1,0(a0); sb a1, 4(t4)
    la a0, candle_y ; lbu a1,0(a0); sb a1, 5(t4)
    la a0, monster_x; lbu a1,0(a0); sb a1, 6(t4)
    la a0, monster_y; lbu a1,0(a0); sb a1, 7(t4)
    la a0, has_match; lbu a1,0(a0); sb a1, 8(t4)
    la a0, candle_lit; lbu a1,0(a0); sb a1, 9(t4)
    la a0, fearFactor; lbu a1,0(a0); sb a1,10(t4)
    ret

# Restore seed_state back into live state
.globl restore_seed_state
restore_seed_state:
    la t4, seed_state
    lb a1, 0(t4); la a0, player_x ; sb a1,0(a0)
    lb a1, 1(t4); la a0, player_y ; sb a1,0(a0)
    lb a1, 2(t4); la a0, match_x  ; sb a1,0(a0)
    lb a1, 3(t4); la a0, match_y  ; sb a1,0(a0)
    lb a1, 4(t4); la a0, candle_x ; sb a1,0(a0)
    lb a1, 5(t4); la a0, candle_y ; sb a1,0(a0)
    lb a1, 6(t4); la a0, monster_x; sb a1,0(a0)
    lb a1, 7(t4); la a0, monster_y; sb a1,0(a0)
    lb a1, 8(t4); la a0, has_match; sb a1,0(a0)
    lb a1, 9(t4); la a0, candle_lit; sb a1,0(a0)
    lb a1,10(t4); la a0, fearFactor; sb a1,0(a0)
    ret

# Save current RNG state as the map seed
.globl save_rng_seed
save_rng_seed:
    la  t0, rand_state
    lw  t1, 0(t0)
    la  t2, level_seed
    sw  t1, 0(t2)
    ret

# Restore RNG state from the saved map seed
.globl restore_rng_seed
restore_rng_seed:
    la  t2, level_seed
    lw  t1, 0(t2)
    la  t0, rand_state
    sw  t1, 0(t0)
    ret

.globl prompt_players
prompt_players:
    addi sp, sp, -16
    sw   ra, 12(sp)
.read_again:
    PRINT_STR prompt_players_str
    READ_CHAR t0
    # newline for tidiness
    li a0, 13; li a7, 11; ecall
    li a0, 10; li a7, 11; ecall
    # accept '1'..'8'
    li  t1, '1'
    blt t0, t1, .read_again
    li  t1, 48        # '0'
    addi t1, t1, MAX_PLAYERS   # '0'+MAX_PLAYERS
    bgt t0, t1, .read_again
    # store players_count = digit - '0'
    li  t1, '0'
    sub t0, t0, t1
    la  t2, players_count
    sb  t0, 0(t2)
    lw   ra, 12(sp)
    addi sp, sp, 16
    ret

.globl run_round
run_round:
    addi sp, sp, -28
    sw   ra, 24(sp)
    sw   s0, 20(sp)          # i
    sw   s1, 16(sp)          # n (players_count), preserved across calls
    sw   s2, 12(sp)

    # load and preserve n
    la   t0, players_count
    lbu  t1, 0(t0)
    mv   s1, t1              # s1 = n

    # init order_idx[i] = i
    li   s0, 0
1:  bge  s0, s1, 2f
    la   t2, order_idx
    add  t3, t2, s0
    sb   s0, 0(t3)
    addi s0, s0, 1
    j    1b
2:
    li   s0, 0              # i = 0
.round_loop:
    bge  s0, s1, .done_rounds

    # --- banner ---
    PRINT_STR msg_player_turn1
    mv   t3, s0
    addi t3, t3, 1
    PRINT_INT t3
    PRINT_STR msg_player_turn2

    # --- same map for everyone ---
    jal  ra, restore_rng_seed
    jal  ra, init_game
    jal  ra, draw_board_and_status

    # play until win or death (game_loop returns)
    jal  ra, game_loop

    # record fear score
    la   t4, fearFactor
    lbu  t5, 0(t4)
    la   t6, scores
    add  t6, t6, s0
    sb   t5, 0(t6)
	
	 # ---- Only show "next player" prompt if this isn't the last player ----
    addi t3, s1, -1          # last index = n-1
    beq  s0, t3, .skip_next_prompt

    PRINT_STR msg_next_turn
    READ_CHAR t0              # wait for any key
	
.skip_next_prompt:
    addi s0, s0, 1
    j    .round_loop

.done_rounds:
    lw   s2, 12(sp)
    lw   s1, 16(sp)
    lw   s0, 20(sp)
    lw   ra, 24(sp)
    addi sp, sp, 28
    ret


.globl print_leaderboard
print_leaderboard:
    addi sp, sp, -28
    sw   ra, 24(sp)
    sw   s0, 20(sp)
    sw   s1, 16(sp)
    sw   s2, 12(sp)

    la   t0, players_count
    lbu  t1, 0(t0)          # n

    PRINT_STR msg_leaderboard

    li   s0, 0              # i
.lb_outer:
    bge  s0, t1, .lb_done
    mv   s1, s0             # minIdx = i
    addi s2, s0, 1          # j = i+1
.lb_inner:
    bge  s2, t1, .lb_after_inner

    # idx_j  = order_idx[j]
    la   t2, order_idx
    add  t3, t2, s2
    lbu  t4, 0(t3)

    # idx_min = order_idx[minIdx]
    la   t2, order_idx
    add  t3, t2, s1
    lbu  t5, 0(t3)

    # score_j  = scores[idx_j]
    la   t6, scores
    add  t6, t6, t4
    lbu  a0, 0(t6)

    # score_min = scores[idx_min]
    la   t6, scores
    add  t6, t6, t5
    lbu  a1, 0(t6)

    blt  a0, a1, .lb_set_min
    j    .lb_cont_inner
.lb_set_min:
    mv   s1, s2
.lb_cont_inner:
    addi s2, s2, 1
    j    .lb_inner

.lb_after_inner:
    # swap order_idx[i] <-> order_idx[minIdx]
    beq  s1, s0, .lb_no_swap
    la   t2, order_idx
    add  t3, t2, s0
    lbu  t4, 0(t3)                # tmp = order[i]
    la   t2, order_idx
    add  a2, t2, s1               # second pointer in a2 (legal)
    lbu  a3, 0(a2)                # order[min]
    sb   a3, 0(t3)                # order[i] = order[min]
    sb   t4, 0(a2)                # order[min] = tmp
.lb_no_swap:

    # print: "<rank>: Player <idx+1>  Fear = <score>"
    addi a3, s0, 1                # rank = i+1
    PRINT_INT a3
    PRINT_STR msg_rank_sep

    la   t2, order_idx
    add  t3, t2, s0
    lbu  t4, 0(t3)
    addi t4, t4, 1                # player index + 1
    PRINT_INT t4

    PRINT_STR msg_fear_sep

    la   t2, order_idx
    add  t3, t2, s0
    lbu  t4, 0(t3)
    la   t6, scores
    add  t6, t6, t4
    lbu  a0, 0(t6)
    PRINT_INT a0
    PRINT_NL

    addi s0, s0, 1
    j    .lb_outer

.lb_done:
    lw   s2, 12(sp)
    lw   s1, 16(sp)
    lw   s0, 20(sp)
    lw   ra, 24(sp)
    addi sp, sp, 28
    ret