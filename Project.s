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
# ENHANCEMENTS (to be implemented next in this same file):
# [ ] Enhancement A (Memory): Increase difficulty by supporting N matches/candles/monsters.
# Plan: store arrays of entity positions and a count# spawn non-overlapping# render loop iterates arrays.
# [ ] Enhancement B (Code): Light Safe Zone around a lit candle.
# Plan: radius R (e.g., 1) blocks monster entry# track per-monster border wait# resume chase when player exits.
# NOTE: When implemented, fill the header with (a) which enhancements, (b) labels/line refs, (c) brief how.
# -----------------------------------------------------------------------------

#------------------------------------------------------------------------------
# Macros: (RARS syscalls)
#------------------------------------------------------------------------------
.macro PRINT_STR addr
    li a7, 4
    la a0, \addr
    ecall
.end_macro

.macro PRINT_CHAR reg
    li a7, 11
    mv a0, \reg
    ecall
.end_macro

.macro PRINT_INT reg
    li a7, 1
    mv a0, \reg
    ecall
.end_macro

.macro PRINT_NL reg
    li a7, 11
    li a0, 10
    ecall
.end_macro

.macro READ_CHAR dest
    li a7, 12
    ecall
    mv \dest a0
.end_macro

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

# RNG state (xorshift 32)
rand_state: .word 2463534242 # default seed to use xorshift 32

# UI strings
welcome_msg: .asciz "Welcome to the Haunted house!\n"
                .asciz "You are in a dark room. You can move using W (up), A (left), S (down), D (right).\n"
                .asciz "Press R to restart, Q to quit.\n"
                .asciz "Light the candle (C) using the match (M)\n"
                .asciz "Avoid the shadow monster (X)!\n"
                .asciz "Your fear factor increases by 10 when a shadow monster gets adjacent.\n"
                .asciz "Once your fear factor = 100, the Game is Over\n"
                .asciz "Good luck!\n\n"
                .asciz
status_prefix: .asciz "Status: Fear="
status_mid1: .asciz "Match="
status_mid2: .asciz "Candle="
status_lit: .asciz "lit"
status_unlit: .asciz "unlit"
msg_invalid: .asciz "Cannot move there (Wall)\n"
msg_picked: .asciz "You picked up the match.\n"
msg_lit: .asciz "Candle lit! You have gotten rid of the shadows. Congradulations, You Win!\n"
msg_fear: .asciz "A Shadow Monster was next to you - Your fear increases by 10\n"
msg_over: .asciz "Your fear reached 100. Game over\n"
msg_restart: .asciz "Restarting game ...\n\n"

# 1 byte scratch buffer for printing visual characters
ch_buf: .byte 0


.text
.global _start

_start:
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
    jal ra, init_game
    PRINT_STR welcome_msg
    jal ra, draw_board_and_status
    jal ra, game_loop

    # on return we exit
    lw ra, 12(sp)
    addi sp, sp, 16

    li a7, 10
    ecall
# ------------------------------------------------------------------------------------------
# init_game - (re) initialize the state, make sure to spawn the entities without overlapping
#-------------------------------------------------------------------------------------------
_globl init_game:
    addi sp, sp, -16
    sw ra, 12(sp)

    # Reset the flags and clear
    li t0, 0
    sb t0, fearFactor
    sb t0, has_match
    sb t0, candle_lit

    # width (t4), and height (t5)
    lbu t4, gridsize
    lbu t5, gridsize + 1

    # place the player
1:  mv t0, t4
    jal ra, rand_bounded # a0 <-- 0,...,w-1
    sb a0, player_x
    mv a0, t5
    jal ra, rand_bounded
    sb a0, player_y

    # place the match (cannot be on the player)
2:  mv a0, t4
    jal ra, rand_bounded
    mv t0, a0
    mv a0, t5
    jal ra, rand_bounded
    mv t1, 
    # compare with player position
    lbu t2, player_x
    lbu t3, player_y
    bne t0, t2, 3f
    bne t1, t3, 3f
    j 2b # overlap, retry
3:  sb t0, match_x
    sb t1, match_y

    # place the candle (cannot be on player or match)
4:  mv t0, t4
    jal ra, rand_bounded
    mv t0, a0
    mv a0, t5
    jal ra, rand_bounded
    mv t1, a0

    lbu t2, player_x
    lbu t3, player_y
    beq t0, t2, 4b
    beq t1, t3, 4b

    lbu t2, match_x
    lbu t3, match_y
    beq t0, t2, 4b
    beq t1, t3, 4b

    sb t0, candle_x
    sb t1, candle_y

    # place the shadow monster
5:
    mv t0, a4
    jal ra, rand_bounded
    mv t0, a0
    mv a0, t5
    jal ra, rand_bounded
    mv t1, a0
    #check vs player
    lbu t2, player_x
    lbu t3, player_y
    beq t0, t2, 5b
    beq t1, t3, 5b
    # check vs match
    lbu t2, match_x
    lbu t3, match_y
    beq t0, t2, 5b
    beq t1, t3, 5b
    #check vs candle
    lbu t2, candle_x
    lbu t3, candle_y
    beq t0, t2, 5b
    beq t1, t3, 5b

    sb t0, monster_x
    sb t1, monster_y

    lw ra, 12(sp)
    addi sp, sp, 16
    ret

#---------------------------------------------------------------
# game_loop: process inputs, update the world, render the world
#---------------------------------------------------------------
.globl game_loop:

game_loop:
    addi sp, sp, -32 # allocate 8 spaces in stack
    sw ra, 28(sp)

.loop:
    # read a keystroke
    READ_CHAR t0

    # normalize into upper case if a...z
    li t1, 'a'
    li t2, 'z'
    blt t0, t1, 1f
    bgt t0, t2, 1f
    addi t0, t0, -32 # to uppercase

1: # handle Q/R/W/A/S/D
    li t1, 'Q'
    beq t0, t1, .quit
    li t1, 'R'
    bne t0, t1, 2f
    PRINT_STR msg_restart
    jal ra, init_game
    jal ra, draw_board_and_status
    j .loop

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
    jal ra, try_move_player
    beqz t3, .invalid

    # after the player move, move monster 1 step closer
    jal ra, monster_step_towards_player

    # after moster moves, check if next to player, add 10 to fear factor and respawn
    jal ra, check_shadow_monster_adjacency

    # after updates, redraw the board
    jal ra, draw_board_and_status
    j .loop

.invalid:
    PRINT_STR msg_invalid
    jal ra, draw_board_and_status
    j .loop

.noop:
    # ignore other keys, keep board still visible
    jal ra, draw_board_and_status
    j .loop

.quit:
    lw ra 28(sp)
    addi sp, sp, 32
    ret

#-------------------------------------------------------------------
# try_move_player -> dx = s1, dy = s2, attemps to move within bounds
#   returns t3 = 1 if moved, otherwise
#   also handles pickup and candle lighting (with printed messages)
# ------------------------------------------------------------------
.globl try_move_player:

try_move_player:
    addi sp, sp, -32 # allocate 8 spaces again
    sw ra, 28(sp)

    # load dimensions (again)
    lbu t0, gridsize # width
    lbu t1, grisize+1 # height

    # current position
    lbu t4, player_x
    lbu t5, player_y

    # new position = old + delta(check that 0...w-1, 0...h-1)
    add t6, t4, s1 # newx
    add t7, t5, s2 # newy

    # check that 0<=newx<=w
    bltz t6, .blocked
    bltz t7, .blocked
    bge t6, t0, .blocked
    bge t7, t1, .blocked

    # commit the move
    mv t3, zero
    sb t6, player_x
    sb t7, player_y
    li t3, 1 # moved

    # pickup the match if present and not already holding it
    lbu t2, has_match
    bnez t2, 1f

    lbu t0, match_x
    lbu t1, match_y
    bne t6, t0, 1f
    bne t7, t1, 1f

    li t2, 1
    sb t2, has_match
    PRINT_STR msg_picked

    # hide match by moving off the grid
    li t2, 255
    sb t2, match_x
    sb t3, match_y

1:  # light the candle if on it and have a match, and not already lit
    lbu t0, candle_lit
    bnez t0, 2f
    lbu t2, has_match
    beqz t2, 2f
    lbu t0, candle_x
    lbu t1, candle_y
    bne t6, t0, 2f
    bne t7, t1, 2f
    # light the candle!!!
    li t2, 1
    sb t2, candle_lit
    PRINT_STR msg_lit

2: j .ret

.blocked:
    mv t3, zero

.ret:
    lw ra, sp(28)
    addi sp, sp, 32
    ret

#------------------------------------------------------------------------------
# monster_step_towards_player -> move monster 1 step towards player
# note: step along x if x differs, else step along y
#------------------------------------------------------------------------------
.globl monster_step_towards_player:

monster_step_towards_player:
    addi sp, sp, -16 # allocate 4 spaces in stack for 4 words
    sw ra, 12(sp)

    lbu t0, player_x
    lbu t1, player_y
    lbu t2, monster_x
    lbu t3, monster_y

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
    lbu t6, gridsize # width
    lbu t7, grindsize+1 #height
    #check if t2 in 0...w-1
    bltz t2, 5f
    bge t2, t6, 6f
    j 7f

5:  li t2, 0
    j 7f

6: addi t2, t6, -1

7: # check if t3 in 0...h-1
    bltz t3, 8f
    bge t3, t7, 9f
    j 10f

8:  li t3, 0
    j 10f
 
9:  addi t3, t7, -1

10: sb t2, monster_x
    sb t3, monster_y

    lw ra 12(sp)
    addi sp, sp, 16
    ret

#--------------------------------------------------------------------------------
# check_shadow_monster_adjacency -> if |dx|+|dy| = 1, fear +=10, respawn monster
#   and print fear message if fear >=100, the game is over and end the program
#--------------------------------------------------------------------------------
.globl check_shadow_monster_adjacency

check_shadow_monster_adjacency:
    addi sp, sp, -32 # allocate 8 words to be stored in stack
    sw ra, 28(sp)

    lbu t0, player_x
    lbu t1, player_y
    lbu t2, monster_x
    lbu t3, monster_y

    sub t4, t0, t2 # dx
    sub t5, t1, t3 # dy
    # abs(dx)
    bltz t4, 1f
    mv t6, t4
    j 2f

1:  sub t6, zero, t4

2:  # abs(dy)
    bltz t5, 3f
    mv t7, t5
    j 4f

3:  sub t7, zero, t5

4:  add t6, t6, t7
    li t4, 1
    bne t6, t4, .nohit

    # fear+=10
    lbu t0, fearFactor
    addi t0, t0, 10
    sb t0, fearFactor
    PRINT_STR msg_fear

    # is game over?
    li t1, 100
    blt t0, t1, 5f
    PRINT_STR msg_over
    # a clean exit
    li a7, 10
    ecall

5:  # respawn the monster to a new free cell
    lbu t4, gridsize #width
    lbu t5, gridsize+1 #height

6:  mv t0, t4
    jal ra, rand_bounded
    mv t6, a0 # randomx
    mv a0, t5

    jal ra, rand_bounded
    mv t7, a0 #random y

    # dont allow overlapping with player/candle(if unlit)/match (if not picked up)

    #player
    lbu t0, player_x
    lbu t1, player_y
    beq t6, t0, 6b # reloop
    beq t7 t1, 6b

    # is candle present?
    lbu t2, candle_lit
    bnez t2, 7f

    lbu t0, candle_x
    lbu t1, candle_y
    beq t6, t0, 6b
    beq t7, t1, 6b

7:  # is match present?
    lbu t2, has_match
    bnez t2, 8f

    lbu t0, match_x
    lbu t1, match_y
    beq t6, t0, 6b
    beq t7, t1, 6b

8:  sb t6, monster_x
    sb t7, monster_y

.nohit:
    lw ra sp(28)
    addi sp, sp, 32
    ret


#-------------------------------------------------------------------
# draw_board_and_status -> renders the bordered grid and status line
#-------------------------------------------------------------------
.globl draw_board_and_status

draw_board_and_status:
    addi sp, sp, -48 # allocate for 12 words on stack
    sw ra 44(sp)

    lbu t0 gridsize #width
    lbu t1 gridsize+1 #height

    #top border: (width+2) '#'
    li t2, '#'
    addi t3, t0, 2 # count

.top_loop:
    beqz t3, .top_done
    PRINT_CHAR t2
    addi t3, t3, -1
    j .top_loop

.top_done:
    PRINT_NL
    #for each interior row, 
    li t4, 0 # since y = 0...h-1

.row_loop:
    bge t4, t1, .rows_done
    # left border '#'
    li t2 '#'
    PRINT_CHAR t2

    li t5, 0 # x = 0...w-1

.col_loop:
    bge t5, t0, .row_right

    # decide character for cell (x=t5, y=t4)
    # default '.'
    li t6, '.'

    # IF candle is lit, the candle cell becomes '.' dissapears
    lbu t7, candle_lit
    beqz t7, 1f
    # candle hidden
    j 2f

1:  # show candle 'C' if at (x,y)
    lbu a1, candle_x
    lbu a2, candle_y
    bne t5, a1, 2f
    bne t4, a2, 2f
    li t6, 'C'

2: # show match 'M' if not picked up and at (x,y)
    lbu a1, has_match
    bnez, a1, 3f

    lbu a1, match_x
    lbu a2, match_y
    bne t5, a1, 3f
    bne t4, a2, 3f
    li t6, 'M'

3:  #show monster 'X'
    lbu a1, monster_x
    lbu a2, monster_y
    bne t5, a1, 4f
    bne t4, a2, 4f
    li t6, 'X'

4:  # show player 'P' (player overwrites another other symbol visually)
    lbu a1, player_x
    lbu a2, player_y
    bne t5, a1, 5f
    bne t4, a2, 5f
    li t6, 'P'

5:  PRINT_CHAR t6
    addi t5, t5, 1
    j .col_loop

.row_right:
    # right border with '#'
    li t2, '#'
    PRINT_CHAR t2
    PRINT_NL

    addi t4, t4, 1
    j .row_loop

.rows_done:
    # bottom border
    li t2, '#'
    addi t3, t0, 2

.bottom_loop:
    beqz t3, .bottom_done
    PRINT_CHAR t2
    addi t3, t3, -1
    j .bottom_loop

.bottom_done:
    PRINT_NL

    #status line: Fear, Match, Candle
    PRINT_STR status_prefix # prints fear=
    lbu t6, fearFactor
    mv t7, t6
    PRINT_INT t7

    PRINT_STR status_mid1 # prints match=
    lbu t6, has_match
    PRINT_INT t6 # prints 0 or 1

    PRINT_STR status_mid2 # prints candle=
    lbu t6, candle_lit
    beqz t6, .show_unlit
    PRINT_STR status_lit

    j .status_end

.show_unlit:
    PRINT_STR status_unlit

.status_end:
    PRINT_NL

    lw ra, 44(sp)
    addi sp, sp, 48

    ret


#--------------------------------------------------------------------------------
# rand32 - xorshift32 (Marsaglia 2003)
#   returns a0 = a new 32 bit random
# -------------------------------------------------------------------------------
.globl rand32:

rand32:
    lw t0, rand_state
    slli t1, t0, 13
    xor t0, t0, t1
    srli t1, t0, 17
    xor t0, t0, t1
    slli t1, t0, 5
    xor t0, t0, t1
    sw t0, rand_state
    mv a0, t0
    ret

#---------------------------------------------------
# rand_bounded -> a0=max -> returns a0 in [0,MAX-1]
#---------------------------------------------------
.globl rand_bounded:

rand_bounded:
    addi sp, sp, -16 # allocate space for 4 words
    sw ra, 12(sp)

    mv t0, a0
    beqz t0, .rb_done # if MAX==0, return 0 (so we dont divide by 0)

1:  call rand32
    remu a0, a0, t0 # modulus

.rb_done:
    lw ra 12(sp)
    addi sp, sp, 16
    ret

#-----------------------------------------------------------
# seed_from_time - seeds the rand_state with time syscall 30
#-----------------------------------------------------------
.globl seed_from_time:

seed_from_time:
    li a7, 30
    ecall
    beqz a0, 1f
    sw a0, rand_state

1:  ret





























# _main:
#     # main method where we run our code sequentially
#     li a7, 4
#     la a0, startingPrompt
#     ecall 


#     li a7, 8 # read string syscall
#     ecall
#     mv t0, a0 # move the input to t0 for processing

#     # TODO: Process the input in t0 and update the game state accordingly

#     j exit

# _print_board:
#     # function to print the board at start
#     addi sp, sp, -16 # allocate stack space for 4 integers
#     la a0, gridsize  # load address of gridsize
#     lw a1, 0(a0)     # load width
#     lw a2, 1(a0)     # load height

#     # TODO: Print the game board using the loaded dimensions to be constantly updated while the player moves
    
#     ret

# # --- GAMEPLAY FUNCTIONS ---
# move_character:
#     # move the character based on user input of W, A, S, D and updates its current position (coordinates) 
#     # this should run every time user inputs a move command based on keyboard input (program Loop should always be calling this function to update character position))
#     ret

# increase_fear_factor:
#     # increase the fear factor when the character picks up an item
#     ret

# increase_match_count:
#     # increase the match count when the character picks up a match
#     ret


# # messages to be printed on console
# invalid_move_message:
#     # print a message when the user makes an invalid move
#     ret

# increase_fear_factor_message:
#     # print a message when the fear factor increases
#     ret

# picked_up_match_message:
#     # print a message when the user picks up the match
#     ret




# exit:
#     li a7, 10
#     ecall
    
    
# # --- HELPER FUNCTIONS ---
# # Feel free to use, modify, or add to them however you see fit.
     
# # Arguments: an integer MAX in a0
# # Return: A number from 0 (inclusive) to MAX (exclusive)
# notrand:
#     mv t0, a0
#     li a7, 30
#     ecall             # time syscall (returns milliseconds)
#     remu a0, a0, t0   # modulus on bottom bits 
#     li a7, 32
#     ecall             # sleeping to try to generate a different number
#     jr ra
