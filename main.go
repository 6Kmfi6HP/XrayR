package main

import (
	log "github.com/sirupsen/logrus"

	"github.com/6Kmfi6HP/XrayR/cmd"
)

func main() {
	if err := cmd.Execute(); err != nil {
		log.Fatal(err)
	}
}
