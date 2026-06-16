include ../../config.mak

CXXFLAGS += -std=c++17 -Wall -g  -I.. -I../melted++ `pkg-config mlt++-7 --cflags`
LDFLAGS  += -L../melted++ -lmelted++ -L../melted -lmelted -L../mvcp -lmvcp `pkg-config mlt++-7 --libs`
CC=c++

all:		server

server:		server.o

server.o:	server.cpp

clean:
	$(RM) server server.o

distclean: clean

install:

uninstall:
