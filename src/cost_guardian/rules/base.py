from abc import ABC, abstractmethod
from sqlite3 import register_converter


class BaseRule(ABC):

    def __init__(self, region):
        self.region = region

    @abstractmethod
    def run(self):
        pass