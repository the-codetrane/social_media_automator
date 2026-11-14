// Configure your import map in config/importmap.rb. Read more: https://github.com/rails/importmap-rails
import "@hotwired/turbo-rails"
import "controllers"
import "Chart.bundle"
import "chartkick"
import { Turbo } from "@hotwired/turbo-rails"
import { useStyledConfirm } from "component_library_2100"
// Every data-turbo-confirm opens the layout's styled dialog instead of the browser's confirm().
useStyledConfirm(Turbo)
