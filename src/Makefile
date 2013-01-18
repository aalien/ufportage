TARGET = ufportage
OBJS = ufportage.o portage.o
CC = fpc
INSTALL = install
INSTALLOPTS = -s
RM = rm
RMOPTS = -rf
BINDIR = /usr/bin/

all:  $(TARGET)

# In Pascal, we dont need to ponder which files to compile.
# Just compile the main program source and compiler will do the rest.
$(TARGET):
	$(CC) $(TARGET).pas -o$(TARGET)

install:
	$(INSTALL) $(INSTALLOPTS) -m 755 $(TARGET) $(BINDIR)

uninstall:
	$(RM) $(RMOPTS) $(BINDIR)$(TARGET)

clean:
	$(RM) $(RMOPTS) $(TARGET) $(OBJS)

debug:
	$(CC) $(TARGET).pas -dDEBUG -o$(TARGET)
