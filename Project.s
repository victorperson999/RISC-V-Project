.data
gridsize: .byte 8,8
character: .byte 0,0
match: .byte 0,0
stick: .byte 0,0
shadowMonster: .byte 0,0
fearFactor: .byte 0

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
