.data
gridsize: .byte 8,8
character: .byte 0,0
match: .byte 0,0
stick: .byte 0,0
shadowMonster: .byte 0,0
fearFactor: .byte 0

startingPrompt .string "Welcome to the Haunted House!\n"
                 .string "You are in a dark room. You can move using W (up), A (left), S (down), D (right).\n"
                 .string "Find the match (M) and stick (T) to increase your fear factor.\n"
                 .string "Avoid the shadow monster (X)!\n"
                 .string "Press R to restart the game at any time.\n"
                 .string "Good luck!\n\n"

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

    # COMMENTS:
    # add needed methods first

_main:
    # main method where we run our code sequentially
    li a7, 4
    la a0, startingPrompt
    ecall 

    li a7, 8 # read string syscall
    ecall





    j exit

_print_board:
    # function to print the board
    addi sp, sp, -16 # allocate stack space for 4 integers
    la a0, gridsize  # load address of gridsize
    lw a1, 0(a0)     # load width
    lw a2, 1(a0)     # load height
    # TODO: Print the game board using the loaded dimensions
    ret

# --- GAMEPLAY FUNCTIONS ---
move_character:
    # move the character based on user input of W, A, S, D and updates its current position (coordinates)
    ret

increase_fear_factor:
    # increase the fear factor when the character picks up an item
    ret

increase_match_count:
    # increase the match count when the character picks up a match
    ret


# messages to be printed on console
invalid_move_message:
    # print a message when the user makes an invalid move
    ret

increase_fear_factor_message:
    # print a message when the fear factor increases
    ret

picked_up_match_message:
    # print a message when the user picks up the match
    ret


exit:
    li a7, 10
    ecall
    
    
# --- HELPER FUNCTIONS ---
# Feel free to use, modify, or add to them however you see fit.
     
# Arguments: an integer MAX in a0
# Return: A number from 0 (inclusive) to MAX (exclusive)
notrand:
    mv t0, a0
    li a7, 30
    ecall             # time syscall (returns milliseconds)
    remu a0, a0, t0   # modulus on bottom bits 
    li a7, 32
    ecall             # sleeping to try to generate a different number
    jr ra
